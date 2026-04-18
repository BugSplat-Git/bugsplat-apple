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


@interface BugSplatHangTracker ()
@property (atomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, weak) id<BugSplatHangTrackerDelegate> delegate;
@property (nonatomic, copy, nullable) BOOL(^isDebuggerAttachedBlock)(void);
@property (nonatomic, copy, nullable) BOOL(^isAppActiveBlock)(void);
@property (nonatomic, strong, nullable) NSThread *watchdogThread;
@end


@implementation BugSplatHangTracker {
    // Wall-clock timestamp (CFAbsoluteTime) of the last AfterWaiting transition.
    // 0.0 means the runloop is currently idle / waiting.
    _Atomic(double) _processingStartWallClock;

    // Set to YES once a hang has been reported for the current processing window.
    // Cleared in BeforeWaiting to re-arm detection for the next processing window.
    _Atomic(bool) _hangReportedForCurrentWindow;

    // Signal from -stop to the watchdog thread.
    _Atomic(bool) _shouldStop;

    CFRunLoopObserverRef _observer;
}

- (instancetype)initWithThresholdSeconds:(NSTimeInterval)thresholdSeconds
                                 delegate:(id<BugSplatHangTrackerDelegate>)delegate
                   isDebuggerAttachedBlock:(BOOL(^)(void))isDebuggerAttachedBlock
                         isAppActiveBlock:(BOOL(^)(void))isAppActiveBlock {
    if (self = [super init]) {
        _thresholdSeconds = thresholdSeconds < kMinThresholdSeconds ? kMinThresholdSeconds : thresholdSeconds;
        _delegate = delegate;
        _isDebuggerAttachedBlock = [isDebuggerAttachedBlock copy];
        _isAppActiveBlock = [isAppActiveBlock copy];
        atomic_init(&_processingStartWallClock, 0.0);
        atomic_init(&_hangReportedForCurrentWindow, false);
        atomic_init(&_shouldStop, false);
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

    // Seed the processing start timestamp so that if we are already executing main-thread
    // work outside a runloop (e.g., during app startup or in unit tests), a hang is still
    // detectable before the first runloop transition.
    atomic_store(&_processingStartWallClock, CFAbsoluteTimeGetCurrent());
    atomic_store(&_hangReportedForCurrentWindow, false);

    [self installRunLoopObserver];

    atomic_store(&_shouldStop, false);
    NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(watchdogThreadMain) object:nil];
    thread.name = @"com.bugsplat.hang-tracker";
    thread.qualityOfService = NSQualityOfServiceUtility;
    self.watchdogThread = thread;
    self.running = YES;
    [thread start];
}

- (void)stop {
    if (!self.isRunning) {
        return;
    }
    self.running = NO;
    atomic_store(&_shouldStop, true);
    [self removeRunLoopObserver];
    self.watchdogThread = nil;
}

#pragma mark - CFRunLoopObserver

- (void)installRunLoopObserver {
    if (_observer) {
        return;
    }

    __weak __typeof(self) weakSelf = self;
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(
        kCFAllocatorDefault,
        kCFRunLoopEntry | kCFRunLoopAfterWaiting | kCFRunLoopBeforeWaiting | kCFRunLoopExit,
        true,  // repeats
        0,     // order
        ^(CFRunLoopObserverRef obs, CFRunLoopActivity activity) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf handleRunLoopActivity:activity];
        });

    if (!observer) {
        return;
    }

    CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
    CFRunLoopAddObserver(mainRunLoop, observer, kCFRunLoopCommonModes);
    _observer = observer;
}

- (void)removeRunLoopObserver {
    if (!_observer) {
        return;
    }
    CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
    CFRunLoopRemoveObserver(mainRunLoop, _observer, kCFRunLoopCommonModes);
    CFRelease(_observer);
    _observer = NULL;
}

- (void)handleRunLoopActivity:(CFRunLoopActivity)activity {
    // Called on the main thread.
    //
    // The runloop signals we care about:
    //   Entry / AfterWaiting / Exit -> main is executing (or resumed / transitioned
    //       between runloop modes / left a nested runloop). Mark a new processing
    //       window so the watchdog can time it.
    //   BeforeWaiting -> main is about to sleep waiting for input. Not a hang;
    //       clear the timestamp.
    //
    // Exit is included because after a nested runloop returns, the main thread is
    // typically still busy executing synchronous code outside that runloop - we
    // want that time window to be visible to the watchdog.
    bool wasReported = atomic_exchange(&_hangReportedForCurrentWindow, false);

    if (activity == kCFRunLoopBeforeWaiting) {
        atomic_store(&_processingStartWallClock, 0.0);
    } else {
        atomic_store(&_processingStartWallClock, CFAbsoluteTimeGetCurrent());
    }

    if (!wasReported) {
        return;
    }

    // Previous processing window had a hang reported and we have now transitioned
    // to a new state - whether idle or a fresh processing window, the main thread
    // unblocked. Notify the delegate so any persisted report can be removed.
    id<BugSplatHangTrackerDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(hangTrackerDidRecoverFromHang:)]) {
        return;
    }

    // Dispatch off the main thread so the delegate can do disk I/O without
    // blocking the runloop we just observed recovering.
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [delegate hangTrackerDidRecoverFromHang:strongSelf];
        }
    });
}

#pragma mark - Watchdog Thread

- (void)watchdogThreadMain {
    NSTimeInterval pollInterval = BugSplatHangPollInterval(self.thresholdSeconds);
    NSTimeInterval threshold = self.thresholdSeconds;
    CFAbsoluteTime previousPollEnd = CFAbsoluteTimeGetCurrent();

    while (!atomic_load(&_shouldStop)) {
        @autoreleasepool {
            [NSThread sleepForTimeInterval:pollInterval];

            if (atomic_load(&_shouldStop)) {
                break;
            }

            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            CFAbsoluteTime expectedWake = previousPollEnd + pollInterval;
            NSTimeInterval overshoot = now - expectedWake;
            previousPollEnd = now;

            // Wall-clock guard: if we overslept by more than the threshold,
            // the device likely slept or the process was suspended. Skip.
            if (overshoot > threshold) {
                // Reset so we don't treat the long gap itself as a hang.
                atomic_store(&_processingStartWallClock, now);
                continue;
            }

            // Debugger guard.
            BOOL(^debuggerCheck)(void) = self.isDebuggerAttachedBlock;
            if (debuggerCheck && debuggerCheck()) {
                continue;
            }

            // App-active guard.
            BOOL(^activeCheck)(void) = self.isAppActiveBlock;
            if (activeCheck && !activeCheck()) {
                continue;
            }

            // Throttle: only one hang report per processing window.
            if (atomic_load(&_hangReportedForCurrentWindow)) {
                continue;
            }

            double startWallClock = atomic_load(&_processingStartWallClock);
            if (startWallClock == 0.0) {
                // Main runloop is idle / waiting - healthy.
                continue;
            }

            NSTimeInterval elapsed = now - startWallClock;
            if (elapsed < threshold) {
                continue;
            }

            // Claim the window so we only fire once per hang.
            bool expected = false;
            if (!atomic_compare_exchange_strong(&_hangReportedForCurrentWindow, &expected, true)) {
                continue;
            }

            [self notifyDelegateOfHangWithDuration:elapsed];
        }
    }
}

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
