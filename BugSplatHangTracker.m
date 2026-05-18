//
//  BugSplatHangTracker.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BugSplatHangTracker.h"

#import <CoreFoundation/CoreFoundation.h>
#import <stdatomic.h>
#import <pthread.h>
#import <mach/mach.h>

#if TARGET_OS_IOS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#endif

static const NSTimeInterval kMinThresholdSeconds = 0.1;
static const NSTimeInterval kMinPollIntervalSeconds = 0.1;

/// Poll interval is threshold / 5, clamped to a reasonable floor.
static inline NSTimeInterval BugSplatHangPollInterval(NSTimeInterval threshold) {
    NSTimeInterval interval = threshold / 5.0;
    return interval < kMinPollIntervalSeconds ? kMinPollIntervalSeconds : interval;
}

/// Maximum number of consecutive unanswered pings before declaring a hang.
/// `ceil(threshold / pollInterval)` ensures the elapsed time covered by the
/// unanswered pings is at least `threshold`.
static inline NSInteger BugSplatHangMaxUnansweredPings(NSTimeInterval threshold) {
    NSTimeInterval pollInterval = BugSplatHangPollInterval(threshold);
    NSInteger n = (NSInteger)ceil(threshold / pollInterval);
    return n < 1 ? 1 : n;
}


@interface BugSplatHangTracker ()
@property (atomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, weak) id<BugSplatHangTrackerDelegate> delegate;
@property (nonatomic, copy, nullable) BOOL(^isDebuggerAttachedBlock)(void);
@property (nonatomic, copy, nullable) BOOL(^isAppActiveBlock)(void);
@property (nonatomic, copy) CFAbsoluteTime(^clockBlock)(void);
@property (nonatomic, copy) void(^recoveryDispatcher)(dispatch_block_t);
@property (nonatomic, copy) void(^pingDispatcher)(dispatch_block_t);
@property (nonatomic, strong, nullable) NSThread *watchdogThread;
@end


@implementation BugSplatHangTracker {
    // Number of consecutive watchdog polls during which the main thread has
    // not serviced a dispatched ping. Each poll dispatches a ping block to the
    // main queue; the ping block resets this counter to 0. If the counter
    // reaches the threshold-derived limit, the main thread has been blocked
    // for at least `thresholdSeconds`.
    _Atomic(int32_t) _unansweredPings;

    // Set to YES once a hang has been reported for the current window;
    // cleared by the next pong (which also triggers a recovery callback).
    _Atomic(bool) _hangReportedForCurrentWindow;
}

- (instancetype)initWithThresholdSeconds:(NSTimeInterval)thresholdSeconds
                                 delegate:(id<BugSplatHangTrackerDelegate>)delegate
                   isDebuggerAttachedBlock:(BOOL(^)(void))isDebuggerAttachedBlock
                         isAppActiveBlock:(BOOL(^)(void))isAppActiveBlock {
    return [self initWithThresholdSeconds:thresholdSeconds
                                 delegate:delegate
                   isDebuggerAttachedBlock:isDebuggerAttachedBlock
                          isAppActiveBlock:isAppActiveBlock
                                clockBlock:nil
                        recoveryDispatcher:nil
                             pingDispatcher:nil];
}

- (instancetype)initWithThresholdSeconds:(NSTimeInterval)thresholdSeconds
                                 delegate:(id<BugSplatHangTrackerDelegate>)delegate
                   isDebuggerAttachedBlock:(BOOL(^)(void))isDebuggerAttachedBlock
                         isAppActiveBlock:(BOOL(^)(void))isAppActiveBlock
                                clockBlock:(CFAbsoluteTime(^)(void))clockBlock
                       recoveryDispatcher:(void(^)(dispatch_block_t))recoveryDispatcher
                            pingDispatcher:(void(^)(dispatch_block_t))pingDispatcher {
    if (self = [super init]) {
        _thresholdSeconds = thresholdSeconds < kMinThresholdSeconds ? kMinThresholdSeconds : thresholdSeconds;
        _delegate = delegate;
        _isDebuggerAttachedBlock = [isDebuggerAttachedBlock copy];
        _isAppActiveBlock = [isAppActiveBlock copy];
        if (clockBlock) {
            _clockBlock = [clockBlock copy];
        } else {
            _clockBlock = ^CFAbsoluteTime{ return CFAbsoluteTimeGetCurrent(); };
        }
        if (recoveryDispatcher) {
            _recoveryDispatcher = [recoveryDispatcher copy];
        } else {
            _recoveryDispatcher = ^(dispatch_block_t b) {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), b);
            };
        }
        if (pingDispatcher) {
            _pingDispatcher = [pingDispatcher copy];
        } else {
            _pingDispatcher = ^(dispatch_block_t b) {
                dispatch_async(dispatch_get_main_queue(), b);
            };
        }
        atomic_init(&_unansweredPings, 0);
        atomic_init(&_hangReportedForCurrentWindow, false);
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Public API

- (void)start {
    NSAssert([NSThread isMainThread], @"BugSplatHangTracker -start must be called on the main thread");
    if (self.isRunning) {
        return;
    }
    self.running = YES;
    atomic_store(&_unansweredPings, 0);
    atomic_store(&_hangReportedForCurrentWindow, false);

    NSThread *thread = [[NSThread alloc] initWithTarget:self
                                               selector:@selector(watchdogThreadMain)
                                                 object:nil];
    thread.name = @"com.bugsplat.hang-tracker";
    thread.qualityOfService = NSQualityOfServiceUtility;
    self.watchdogThread = thread;
    [thread start];
}

- (void)stop {
    if (!self.isRunning) {
        return;
    }
    // Flipping running=NO causes the watchdog loop to exit on its next
    // iteration. The thread retains self until it returns, so no in-flight
    // ping callback can call into a deallocated tracker.
    self.running = NO;
    self.watchdogThread = nil;
}

#pragma mark - Watchdog Thread

- (void)watchdogThreadMain {
    NSTimeInterval pollInterval = BugSplatHangPollInterval(self.thresholdSeconds);

    __weak __typeof(self) weakSelf = self;
    dispatch_block_t ping = ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleMainQueuePong];
    };

    while (self.isRunning) {
        @autoreleasepool {
            // Send a ping to the main queue. If the main thread is healthy it
            // will service this block before the next poll; if it is hung the
            // block will sit on the main queue and our counter will tick up.
            self.pingDispatcher(ping);

            CFAbsoluteTime sleepStart = self.clockBlock();
            [NSThread sleepForTimeInterval:pollInterval];

            if (!self.isRunning) {
                break;
            }

            CFAbsoluteTime sleepEnd = self.clockBlock();
            [self _processPollWithActualSleepDuration:(sleepEnd - sleepStart)];
        }
    }
}

/// Per-poll watchdog logic, factored out of the thread loop so tests can drive
/// it deterministically without spawning a real thread.
- (void)_processPollWithActualSleepDuration:(NSTimeInterval)actualSleep {
    NSTimeInterval threshold = self.thresholdSeconds;
    NSInteger maxUnansweredPings = BugSplatHangMaxUnansweredPings(threshold);

    // Suspension guard: if our sleep took noticeably longer than the threshold,
    // the device was suspended or the process was put to sleep. Reset state -
    // we don't want the unanswered backlog to fire a "hang" the moment we wake.
    if (actualSleep > threshold * 2.0) {
        atomic_store(&_unansweredPings, 0);
        return;
    }

    // Debugger guard.
    BOOL(^debuggerCheck)(void) = self.isDebuggerAttachedBlock;
    if (debuggerCheck && debuggerCheck()) {
        atomic_store(&_unansweredPings, 0);
        return;
    }

    // App-active guard.
    BOOL(^activeCheck)(void) = self.isAppActiveBlock;
    if (activeCheck && !activeCheck()) {
        atomic_store(&_unansweredPings, 0);
        return;
    }

    // Throttle: only one hang report per processing window.
    if (atomic_load(&_hangReportedForCurrentWindow)) {
        return;
    }

    int32_t pings = atomic_fetch_add(&_unansweredPings, 1) + 1;
    if (pings < maxUnansweredPings) {
        return;
    }

    // Claim the window so we only fire once per hang.
    bool expected = false;
    if (!atomic_compare_exchange_strong(&_hangReportedForCurrentWindow, &expected, true)) {
        return;
    }

    NSTimeInterval duration = pings * BugSplatHangPollInterval(threshold);
    [self notifyDelegateOfHangWithDuration:duration];
}

/// Called on the main thread when the ping block runs (i.e. main is responsive).
/// Resets the unanswered-ping counter and, if a hang had been reported for the
/// just-ended window, dispatches a recovery callback so the integrator can
/// discard any persisted hang report.
- (void)handleMainQueuePong {
    atomic_store(&_unansweredPings, 0);
    bool wasReported = atomic_exchange(&_hangReportedForCurrentWindow, false);
    if (!wasReported) {
        return;
    }

    id<BugSplatHangTrackerDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(hangTrackerDidRecoverFromHang:)]) {
        return;
    }

    __weak __typeof(self) weakSelf = self;
    self.recoveryDispatcher(^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [delegate hangTrackerDidRecoverFromHang:strongSelf];
        }
    });
}

#pragma mark - Notification

- (void)notifyDelegateOfHangWithDuration:(NSTimeInterval)duration {
    id<BugSplatHangTrackerDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(hangTracker:didDetectHangWithDuration:appState:)]) {
        return;
    }

    NSString *appState = [self currentAppStateDescription];
    [delegate hangTracker:self didDetectHangWithDuration:duration appState:appState];
}

- (NSString *)currentAppStateDescription {
    BOOL(^activeCheck)(void) = self.isAppActiveBlock;
    if (!activeCheck) {
        return @"unknown";
    }
    return activeCheck() ? @"active" : @"background";
}

@end
