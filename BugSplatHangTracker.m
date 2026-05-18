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

/// Floor for the "device slept / process suspended" guard. Scheduler jitter on
/// loaded CI machines can easily exceed the hang threshold (which may be a few
/// hundred ms in tests), so the suspension guard uses a much larger value.
static const NSTimeInterval kMinSuspensionOvershootSeconds = 2.0;

/// Poll interval is threshold / 5, clamped to a reasonable floor.
static inline NSTimeInterval BugSplatHangPollInterval(NSTimeInterval threshold) {
    NSTimeInterval interval = threshold / 5.0;
    return interval < kMinPollIntervalSeconds ? kMinPollIntervalSeconds : interval;
}

/// Overshoot beyond this value is treated as the device having slept or the
/// process having been suspended, rather than a legitimate hang.
static inline NSTimeInterval BugSplatHangSuspensionOvershoot(NSTimeInterval threshold) {
    NSTimeInterval guard = threshold * 5.0;
    return guard < kMinSuspensionOvershootSeconds ? kMinSuspensionOvershootSeconds : guard;
}


@interface BugSplatHangTracker ()
@property (atomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, weak) id<BugSplatHangTrackerDelegate> delegate;
@property (nonatomic, copy, nullable) BOOL(^isDebuggerAttachedBlock)(void);
@property (nonatomic, copy, nullable) BOOL(^isAppActiveBlock)(void);
@property (nonatomic, copy) CFAbsoluteTime(^clockBlock)(void);
@property (nonatomic, copy) void(^recoveryDispatcher)(dispatch_block_t);
@property (nonatomic, strong, nullable) NSThread *watchdogThread;
@end


@implementation BugSplatHangTracker {
    // Wall-clock timestamp (via clockBlock) of the last AfterWaiting transition.
    // 0.0 means the runloop is currently idle / waiting.
    _Atomic(double) _processingStartWallClock;

    // Set to YES once a hang has been reported for the current processing window.
    // Cleared in BeforeWaiting to re-arm detection for the next processing window.
    _Atomic(bool) _hangReportedForCurrentWindow;

    // Monotonically increasing generation. Every -start captures the current value
    // for its own watchdog thread; -stop bumps it, which signals the running thread
    // to exit on its next iteration. This is per-thread rather than a shared
    // boolean so that stop/start in quick succession cannot revive an old thread.
    _Atomic(uint64_t) _watchdogGeneration;

    // Per-tracker state for the suspension-overshoot heuristic. Stored on self
    // (rather than as locals in watchdogThreadMain) so tests can drive single
    // polls via -_pollAtTime: without spawning a real thread.
    _Atomic(double) _previousPollEnd;
    _Atomic(bool) _hasPolledOnce;

    CFRunLoopObserverRef _observer;
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
                        recoveryDispatcher:nil];
}

- (instancetype)initWithThresholdSeconds:(NSTimeInterval)thresholdSeconds
                                 delegate:(id<BugSplatHangTrackerDelegate>)delegate
                   isDebuggerAttachedBlock:(BOOL(^)(void))isDebuggerAttachedBlock
                         isAppActiveBlock:(BOOL(^)(void))isAppActiveBlock
                                clockBlock:(CFAbsoluteTime(^)(void))clockBlock
                       recoveryDispatcher:(void(^)(dispatch_block_t))recoveryDispatcher {
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
        atomic_init(&_processingStartWallClock, 0.0);
        atomic_init(&_hangReportedForCurrentWindow, false);
        atomic_init(&_watchdogGeneration, 0);
        atomic_init(&_previousPollEnd, 0.0);
        atomic_init(&_hasPolledOnce, false);
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
    CFAbsoluteTime now = self.clockBlock();
    atomic_store(&_processingStartWallClock, now);
    atomic_store(&_hangReportedForCurrentWindow, false);
    atomic_store(&_previousPollEnd, now);
    atomic_store(&_hasPolledOnce, false);

    [self installRunLoopObserver];

    uint64_t generation = atomic_fetch_add(&_watchdogGeneration, 1) + 1;
    NSThread *thread = [[NSThread alloc] initWithTarget:self
                                               selector:@selector(watchdogThreadMain:)
                                                 object:@(generation)];
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
    // Bumping the generation signals any running watchdog thread (and any future
    // thread that has not yet observed the bump) to exit on its next iteration.
    atomic_fetch_add(&_watchdogGeneration, 1);
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
    // Called on the main thread (or, in tests, from -_simulateRunLoopActivity:).
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
        atomic_store(&_processingStartWallClock, self.clockBlock());
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
    // blocking the runloop we just observed recovering. Tests inject a
    // synchronous dispatcher so recovery is observable inline.
    __weak __typeof(self) weakSelf = self;
    self.recoveryDispatcher(^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [delegate hangTrackerDidRecoverFromHang:strongSelf];
        }
    });
}

#pragma mark - Watchdog Thread

- (void)watchdogThreadMain:(NSNumber *)generationNumber {
    uint64_t myGeneration = generationNumber.unsignedLongLongValue;
    NSTimeInterval pollInterval = BugSplatHangPollInterval(self.thresholdSeconds);

    while (atomic_load(&_watchdogGeneration) == myGeneration) {
        @autoreleasepool {
            [NSThread sleepForTimeInterval:pollInterval];

            if (atomic_load(&_watchdogGeneration) != myGeneration) {
                break;
            }

            [self _pollAtTime:self.clockBlock()];
        }
    }
}

/// Runs one iteration of the watchdog state machine using the supplied wall-clock
/// time. The watchdog thread calls this with `clockBlock()`; tests call it with
/// a deterministic value to make detection / throttling / suspension behavior
/// observable without depending on real thread scheduling.
- (void)_pollAtTime:(CFAbsoluteTime)now {
    NSTimeInterval pollInterval = BugSplatHangPollInterval(self.thresholdSeconds);
    NSTimeInterval threshold = self.thresholdSeconds;
    NSTimeInterval suspensionOvershoot = BugSplatHangSuspensionOvershoot(threshold);

    CFAbsoluteTime previousPollEnd = atomic_load(&_previousPollEnd);
    CFAbsoluteTime expectedWake = previousPollEnd + pollInterval;
    NSTimeInterval overshoot = now - expectedWake;
    atomic_store(&_previousPollEnd, now);

    // Wall-clock guard: if we overslept far beyond the poll interval, the device
    // likely slept or the process was suspended. Skip. Skipped on the first poll
    // because previousPollEnd was seeded when the watchdog started, not at first
    // wake - a slow initial scheduling event (common on loaded CI runners) would
    // otherwise falsely trip the guard and reset the processing-start timestamp,
    // causing the tracker to miss a hang already in progress on the main thread.
    bool hadPolledBefore = atomic_exchange(&_hasPolledOnce, true);
    if (hadPolledBefore && overshoot > suspensionOvershoot) {
        // Reset so we don't treat the long gap itself as a hang.
        atomic_store(&_processingStartWallClock, now);
        return;
    }

    // Debugger guard.
    BOOL(^debuggerCheck)(void) = self.isDebuggerAttachedBlock;
    if (debuggerCheck && debuggerCheck()) {
        return;
    }

    // App-active guard.
    BOOL(^activeCheck)(void) = self.isAppActiveBlock;
    if (activeCheck && !activeCheck()) {
        return;
    }

    // Throttle: only one hang report per processing window.
    if (atomic_load(&_hangReportedForCurrentWindow)) {
        return;
    }

    double startWallClock = atomic_load(&_processingStartWallClock);
    if (startWallClock == 0.0) {
        // Main runloop is idle / waiting - healthy.
        return;
    }

    NSTimeInterval elapsed = now - startWallClock;
    if (elapsed < threshold) {
        return;
    }

    // Claim the window so we only fire once per hang.
    bool expected = false;
    if (!atomic_compare_exchange_strong(&_hangReportedForCurrentWindow, &expected, true)) {
        return;
    }

    [self notifyDelegateOfHangWithDuration:elapsed];
}

/// Test helper: invoke the runloop-activity handler synchronously without
/// installing a real CFRunLoopObserver.
- (void)_simulateRunLoopActivity:(CFRunLoopActivity)activity {
    [self handleRunLoopActivity:activity];
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
