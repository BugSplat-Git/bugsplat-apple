//
//  BugSplatHangTrackerTests.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <CoreFoundation/CoreFoundation.h>
#import "BugSplatHangTracker.h"


/// Private testing surface. Implementations live in `BugSplatHangTracker.m`;
/// this category just makes them visible to the test compilation unit so we can
/// drive the state machine without spawning a real watchdog thread or relying
/// on real wall-clock timing.
@interface BugSplatHangTracker (Testing)
- (instancetype)initWithThresholdSeconds:(NSTimeInterval)thresholdSeconds
                                 delegate:(id<BugSplatHangTrackerDelegate>)delegate
                   isDebuggerAttachedBlock:(BOOL(^)(void))isDebuggerAttachedBlock
                         isAppActiveBlock:(BOOL(^)(void))isAppActiveBlock
                                clockBlock:(CFAbsoluteTime(^)(void))clockBlock
                       recoveryDispatcher:(void(^)(dispatch_block_t))recoveryDispatcher
                            pingDispatcher:(void(^)(dispatch_block_t))pingDispatcher;
- (void)_processPollWithActualSleepDuration:(NSTimeInterval)actualSleep;
- (void)handleMainQueuePong;
@end


@interface MockHangTrackerDelegate : NSObject <BugSplatHangTrackerDelegate>
@property (atomic, assign) NSInteger hangCount;
@property (atomic, assign) NSInteger recoverCount;
@property (atomic, assign) NSTimeInterval lastDuration;
@property (atomic, copy, nullable) NSString *lastAppState;
@end

@implementation MockHangTrackerDelegate

- (void)hangTracker:(BugSplatHangTracker *)tracker
didDetectHangWithDuration:(NSTimeInterval)duration
            appState:(NSString *)appState
{
    self.hangCount += 1;
    self.lastDuration = duration;
    self.lastAppState = appState;
}

- (void)hangTrackerDidRecoverFromHang:(BugSplatHangTracker *)tracker
{
    self.recoverCount += 1;
}

@end


@interface BugSplatHangTrackerTests : XCTestCase
@property (nonatomic, strong) MockHangTrackerDelegate *mockDelegate;
@end

@implementation BugSplatHangTrackerTests

- (void)setUp
{
    [super setUp];
    self.mockDelegate = [[MockHangTrackerDelegate alloc] init];
}

- (BugSplatHangTracker *)trackerWithThreshold:(NSTimeInterval)threshold
                              debuggerAttached:(BOOL)debuggerAttached
                                     appActive:(BOOL)appActive
{
    // Synchronous recovery dispatcher: tests observe recoverCount inline.
    void(^synchronousRecovery)(dispatch_block_t) = ^(dispatch_block_t b) { b(); };
    // No-op ping dispatcher: tests manually drive pongs via -handleMainQueuePong
    // so a "hung" main thread is simulated by simply not calling it.
    void(^noopPing)(dispatch_block_t) = ^(dispatch_block_t b) { /* drop */ };
    // Tests don't need real wall-clock time for the new design; the per-poll
    // logic takes the actual-sleep duration as a parameter. Return 0 just so
    // clockBlock isn't nil if production code ever reaches it.
    CFAbsoluteTime(^zeroClock)(void) = ^{ return (CFAbsoluteTime)0; };
    return [[BugSplatHangTracker alloc] initWithThresholdSeconds:threshold
                                                        delegate:self.mockDelegate
                                          isDebuggerAttachedBlock:^BOOL { return debuggerAttached; }
                                                isAppActiveBlock:^BOOL { return appActive; }
                                                       clockBlock:zeroClock
                                              recoveryDispatcher:synchronousRecovery
                                                   pingDispatcher:noopPing];
}

/// Simulate N consecutive polls where the main thread never serviced the ping.
- (void)pollTracker:(BugSplatHangTracker *)tracker times:(NSInteger)n
{
    // Use a normal (non-suspension) sleep duration so the guard doesn't reset.
    NSTimeInterval normalSleep = tracker.thresholdSeconds / 5.0;
    for (NSInteger i = 0; i < n; i++) {
        [tracker _processPollWithActualSleepDuration:normalSleep];
    }
}

#pragma mark - Initializer

- (void)testInit_ClampsBelowMinimumThreshold
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:0.01 debuggerAttached:NO appActive:YES];
    XCTAssertGreaterThanOrEqual(tracker.thresholdSeconds, 0.1);
}

- (void)testInit_StoresThreshold
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];
    XCTAssertEqualWithAccuracy(tracker.thresholdSeconds, 2.0, 0.0001);
}

- (void)testInit_IsNotRunning
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];
    XCTAssertFalse(tracker.isRunning);
}

#pragma mark - Detection

- (void)testDetectsHang_WhenMainNeverServicesPings
{
    // threshold=2.0, pollInterval=0.4 -> 5 unanswered polls = hang.
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    [self pollTracker:tracker times:4];
    XCTAssertEqual(self.mockDelegate.hangCount, 0);

    [self pollTracker:tracker times:1];
    XCTAssertEqual(self.mockDelegate.hangCount, 1);
    XCTAssertGreaterThanOrEqual(self.mockDelegate.lastDuration, 2.0);
    XCTAssertEqualObjects(self.mockDelegate.lastAppState, @"active");
}

- (void)testDoesNotDetect_WhenMainServicesPingsEachRound
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    // Each poll is followed by a pong - main is responsive.
    for (NSInteger i = 0; i < 10; i++) {
        [self pollTracker:tracker times:1];
        [tracker handleMainQueuePong];
    }

    XCTAssertEqual(self.mockDelegate.hangCount, 0);
}

- (void)testDoesNotDetect_WhenDebuggerAttached
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:YES appActive:YES];

    [self pollTracker:tracker times:10];

    XCTAssertEqual(self.mockDelegate.hangCount, 0);
}

- (void)testDoesNotDetect_WhenAppInactive
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:NO];

    [self pollTracker:tracker times:10];

    XCTAssertEqual(self.mockDelegate.hangCount, 0);
}

#pragma mark - Recovery

- (void)testRecovery_FiresAfterPongFollowingHang
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    [self pollTracker:tracker times:5];
    XCTAssertEqual(self.mockDelegate.hangCount, 1);
    XCTAssertEqual(self.mockDelegate.recoverCount, 0);

    // Main thread services a ping -> recovery fires.
    [tracker handleMainQueuePong];
    XCTAssertEqual(self.mockDelegate.recoverCount, 1);
}

- (void)testRecovery_DoesNotFireWithoutPriorHang
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    [tracker handleMainQueuePong];
    XCTAssertEqual(self.mockDelegate.recoverCount, 0);
}

#pragma mark - Throttle

- (void)testThrottle_OnlyOneHangPerProcessingWindow
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    // Many extra polls inside the same hung window must not refire.
    [self pollTracker:tracker times:20];

    XCTAssertEqual(self.mockDelegate.hangCount, 1);
}

- (void)testThrottle_NewWindowCanFireAgain
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    [self pollTracker:tracker times:5];
    XCTAssertEqual(self.mockDelegate.hangCount, 1);

    // Main resumes long enough for one pong, then hangs again.
    [tracker handleMainQueuePong];
    [self pollTracker:tracker times:5];
    XCTAssertEqual(self.mockDelegate.hangCount, 2);
}

#pragma mark - Suspension guard

- (void)testSuspensionGuard_ResetsCounterAfterLargeSleep
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    // Accumulate some unanswered pings, but not yet enough to fire.
    [self pollTracker:tracker times:3];
    XCTAssertEqual(self.mockDelegate.hangCount, 0);

    // A long sleep (e.g. device suspended) - guard resets the counter.
    [tracker _processPollWithActualSleepDuration:30.0];
    XCTAssertEqual(self.mockDelegate.hangCount, 0);

    // The next few polls should not be enough to fire because the counter
    // was reset by the suspension guard.
    [self pollTracker:tracker times:3];
    XCTAssertEqual(self.mockDelegate.hangCount, 0);
}

- (void)testSuspensionGuard_NormalSleepDoesNotReset
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    // Sleep durations that hover slightly over the poll interval should not
    // count as suspension - real hangs need to be detectable across noisy
    // scheduling.
    NSTimeInterval slightlyLong = 0.45;
    for (NSInteger i = 0; i < 5; i++) {
        [tracker _processPollWithActualSleepDuration:slightlyLong];
    }
    XCTAssertEqual(self.mockDelegate.hangCount, 1);
}

#pragma mark - Start / stop wiring (smoke)

- (void)testStart_SetsRunning
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];
    [tracker start];
    XCTAssertTrue(tracker.isRunning);
    [tracker stop];
}

- (void)testStop_ClearsRunning
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];
    [tracker start];
    [tracker stop];
    XCTAssertFalse(tracker.isRunning);
}

- (void)testStop_IsIdempotent
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];
    [tracker start];
    [tracker stop];
    XCTAssertNoThrow([tracker stop]);
}

@end
