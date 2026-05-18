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
 * queue (dispatched off the main thread so disk I/O can't block recovery). Neither
 * callback runs on the main thread; implementers must not perform UI work directly and
 * should dispatch to a queue if needed.
 */
@protocol BugSplatHangTrackerDelegate <NSObject>

/**
 * Called when the main thread has been unresponsive for at least the configured threshold.
 *
 * @param tracker    The tracker that detected the hang.
 * @param duration   Approximate elapsed time the main thread has been unresponsive, in seconds.
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
 * Monitors the main thread for hangs.
 *
 * A dedicated low-QoS watchdog thread polls every `threshold / 5` seconds (clamped to
 * at least 100ms). Each poll dispatches a small "ping" block to the main queue and
 * increments an atomic counter; the ping block, when serviced, resets that counter.
 * If the counter accumulates enough unanswered pings to cover `thresholdSeconds`, the
 * main thread is considered hung and the delegate is notified. When the main thread
 * later services a ping, a recovery callback fires so the integrator can discard a
 * previously persisted hang report.
 *
 * Callers are expected to invoke `-start` from the main thread.
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
                         isAppActiveBlock:(nullable BOOL(^)(void))isAppActiveBlock;

- (instancetype)init NS_UNAVAILABLE;

/**
 * Start monitoring. Spawns the watchdog thread, which will begin pinging the main
 * queue on its poll interval. Must be called from the main thread.
 */
- (void)start;

/**
 * Stop monitoring. Signals the watchdog thread to exit. Safe to call multiple times.
 */
- (void)stop;

/// YES when the watchdog thread is running.
@property (atomic, readonly, getter=isRunning) BOOL running;

/// Configured threshold in seconds (clamped to >= 0.1).
@property (nonatomic, readonly) NSTimeInterval thresholdSeconds;

@end

NS_ASSUME_NONNULL_END
