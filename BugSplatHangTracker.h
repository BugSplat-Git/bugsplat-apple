//
//  BugSplatHangTracker.h
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class BugSplatHangTracker;

/**
 * Delegate protocol for BugSplatHangTracker.
 *
 * `hangTracker:didDetectHangWithDuration:appState:` is invoked on the tracker's private
 * watchdog thread. `hangTrackerDidRecoverFromHang:` is invoked on a GCD global utility
 * queue (dispatched off the main runloop observer so disk I/O doesn't block recovery).
 * Neither callback runs on the main thread; implementers must not perform UI work directly
 * and should dispatch to a queue if needed.
 */
@protocol BugSplatHangTrackerDelegate <NSObject>

/**
 * Called when the main thread has been unresponsive for at least the configured threshold.
 *
 * @param tracker    The tracker that detected the hang.
 * @param duration   Elapsed time since the main runloop last transitioned, in seconds.
 * @param appState   Short string describing the app state at detection time
 *                   ("active", "background", or "unknown").
 */
- (void)hangTracker:(BugSplatHangTracker *)tracker
didDetectHangWithDuration:(NSTimeInterval)duration
            appState:(NSString *)appState;

/**
 * Called after a hang was detected and the main thread has since resumed.
 * Exists so the integrator can remove a persisted hang report - the main thread recovered
 * and the hang is no longer fatal.
 */
- (void)hangTrackerDidRecoverFromHang:(BugSplatHangTracker *)tracker;

@end


/**
 * Monitors the main runloop for hangs using a CFRunLoopObserver plus a dedicated watchdog thread.
 *
 * Detection is based on the time elapsed between main runloop state transitions
 * (kCFRunLoopAfterWaiting -> kCFRunLoopBeforeWaiting). If the runloop stays in the
 * processing phase for longer than the configured threshold without returning to wait,
 * the delegate is notified.
 *
 * Callers are expected to invoke `-start` from the main thread. The main thread's
 * Mach port is captured at start time for use by any subsequent stack capture.
 */
@interface BugSplatHangTracker : NSObject

/**
 * Initialize a tracker with the given threshold and delegate.
 *
 * @param thresholdSeconds       Main-thread processing duration that triggers a hang.
 *                               Values below 0.1s are clamped to 0.1s.
 * @param delegate               Receives hang / recovery callbacks on the watchdog thread.
 * @param isDebuggerAttachedBlock Optional predicate checked each poll. When it returns YES
 *                               the tracker suppresses detection for that poll. Pass nil
 *                               to disable the guard (useful for tests).
 * @param isAppActiveBlock       Optional predicate checked each poll. When it returns NO
 *                               the tracker suppresses detection for that poll. Pass nil
 *                               to disable the guard (useful for tests or for macOS where
 *                               UIApplication is unavailable).
 */
- (instancetype)initWithThresholdSeconds:(NSTimeInterval)thresholdSeconds
                                 delegate:(id<BugSplatHangTrackerDelegate>)delegate
                   isDebuggerAttachedBlock:(nullable BOOL(^)(void))isDebuggerAttachedBlock
                         isAppActiveBlock:(nullable BOOL(^)(void))isAppActiveBlock NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/**
 * Start monitoring. Installs the CFRunLoopObserver on the main runloop and spawns the
 * watchdog thread. Must be called from the main thread.
 */
- (void)start;

/**
 * Stop monitoring. Removes the observer and signals the watchdog thread to exit.
 * Safe to call multiple times.
 */
- (void)stop;

/// YES when the watchdog thread is running.
@property (atomic, readonly, getter=isRunning) BOOL running;

/// Configured threshold in seconds (clamped to >= 0.1).
@property (nonatomic, readonly) NSTimeInterval thresholdSeconds;

@end

NS_ASSUME_NONNULL_END
