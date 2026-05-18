//
//  BugSplatHangTrackerTests.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <CoreFoundation/CoreFoundation.h>
#import "BugSplatHangTracker.h"


/// Private testing surface. The implementations live in `BugSplatHangTracker.m`;
/// this category just makes them visible to the test compilation unit so we can
/// drive the state machine without spawning a real watchdog thread or relying on
/// real wall-clock timing.
@interface BugSplatHangTracker (Testing)
- (instancetype)initWithThresholdSeconds:(NSTimeInterval)thresholdSeconds
                                 delegate:(id<BugSplatHangTrackerDelegate>)delegate
                   isDebuggerAttachedBlock:(BOOL(^)(void))isDebuggerAttachedBlock
                         isAppActiveBlock:(BOOL(^)(void))isAppActiveBlock
                                clockBlock:(CFAbsoluteTime(^)(void))clockBlock
                       recoveryDispatcher:(void(^)(dispatch_block_t))recoveryDispatcher;
- (void)_pollAtTime:(CFAbsoluteTime)now;
- (void)_simulateRunLoopActivity:(CFRunLoopActivity)activity;
@end


@interface MockHangTrackerDelegate : NSObject <BugSplatHangTrackerDelegate>
@property (atomic, assign) NSInteger hangCount;
@property (atomic, assign) NSInteger recoverCount;
@property (atomic, assign) NSTimeInterval lastDuration;
@property (atomic, copy, nullable) NSString *lastAppState;
@property (atomic, strong, nullable) XCTestExpectation *hangExpectation;
@end

@implementation MockHangTrackerDelegate

- (void)hangTracker:(BugSplatHangTracker *)tracker
didDetectHangWithDuration:(NSTimeInterval)duration
            appState:(NSString *)appState
{
    self.hangCount += 1;
    self.lastDuration = duration;
    self.lastAppState = appState;
    [self.hangExpectation fulfill];
}

- (void)hangTrackerDidRecoverFromHang:(BugSplatHangTracker *)tracker
{
    self.recoverCount += 1;
}

@end


/// Helper that owns a settable "current time" and produces a clock block
/// referencing it. Tests advance the time directly via the `now` property.
@interface FakeClock : NSObject
@property (atomic, assign) CFAbsoluteTime now;
- (CFAbsoluteTime(^)(void))block;
@end

@implementation FakeClock
- (CFAbsoluteTime(^)(void))block {
    __weak __typeof(self) weakSelf = self;
    return ^CFAbsoluteTime{ return weakSelf.now; };
}
@end


@interface BugSplatHangTrackerTests : XCTestCase
@property (nonatomic, strong) MockHangTrackerDelegate *mockDelegate;
@property (nonatomic, strong) FakeClock *clock;
@end

@implementation BugSplatHangTrackerTests

- (void)setUp
{
    [super setUp];
    self.mockDelegate = [[MockHangTrackerDelegate alloc] init];
    self.clock = [[FakeClock alloc] init];
    self.clock.now = 1000.0;
}

- (BugSplatHangTracker *)trackerWithThreshold:(NSTimeInterval)threshold
                              debuggerAttached:(BOOL)debuggerAttached
                                     appActive:(BOOL)appActive
{
    // Synchronous recovery dispatcher so tests can observe `recoverCount` right
    // after the runloop activity that triggers recovery, without polling.
    void(^synchronous)(dispatch_block_t) = ^(dispatch_block_t b) { b(); };
    return [[BugSplatHangTracker alloc] initWithThresholdSeconds:threshold
                                                        delegate:self.mockDelegate
                                          isDebuggerAttachedBlock:^BOOL { return debuggerAttached; }
                                                isAppActiveBlock:^BOOL { return appActive; }
                                                       clockBlock:self.clock.block
                                              recoveryDispatcher:synchronous];
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

- (void)testDetectsHang_WhenProcessingStartIsOlderThanThreshold
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    // Main runloop just entered processing at t=1000.
    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    XCTAssertEqual(self.mockDelegate.hangCount, 0);

    // 1s later: still under the 2s threshold.
    self.clock.now = 1001.0;
    [tracker _pollAtTime:self.clock.now];
    XCTAssertEqual(self.mockDelegate.hangCount, 0);

    // 3s after entry: hung.
    self.clock.now = 1003.0;
    [tracker _pollAtTime:self.clock.now];
    XCTAssertEqual(self.mockDelegate.hangCount, 1);
    XCTAssertGreaterThan(self.mockDelegate.lastDuration, 2.0);
    XCTAssertEqualObjects(self.mockDelegate.lastAppState, @"active");
}

- (void)testDoesNotDetect_WhenStillUnderThreshold
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    self.clock.now = 1001.9;
    [tracker _pollAtTime:self.clock.now];

    XCTAssertEqual(self.mockDelegate.hangCount, 0);
}

- (void)testDoesNotDetect_WhenRunloopIsIdle
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    // BeforeWaiting clears the processing-start timestamp; subsequent polls
    // should never see a hang regardless of how far the clock advances.
    [tracker _simulateRunLoopActivity:kCFRunLoopBeforeWaiting];

    self.clock.now = 1100.0;
    [tracker _pollAtTime:self.clock.now];
    XCTAssertEqual(self.mockDelegate.hangCount, 0);
}

- (void)testDoesNotDetect_WhenDebuggerAttached
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:YES appActive:YES];

    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    self.clock.now = 1010.0;
    [tracker _pollAtTime:self.clock.now];

    XCTAssertEqual(self.mockDelegate.hangCount, 0);
}

- (void)testDoesNotDetect_WhenAppInactive
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:NO];

    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    self.clock.now = 1010.0;
    [tracker _pollAtTime:self.clock.now];

    XCTAssertEqual(self.mockDelegate.hangCount, 0);
}

#pragma mark - Recovery

- (void)testRecovery_FiresAfterRunloopActivityFollowingHang
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    self.clock.now = 1003.0;
    [tracker _pollAtTime:self.clock.now];
    XCTAssertEqual(self.mockDelegate.hangCount, 1);
    XCTAssertEqual(self.mockDelegate.recoverCount, 0);

    // Main thread reaches BeforeWaiting -> recovery fires synchronously thanks
    // to the test dispatcher.
    [tracker _simulateRunLoopActivity:kCFRunLoopBeforeWaiting];
    XCTAssertEqual(self.mockDelegate.recoverCount, 1);
}

- (void)testRecovery_FiresWhenMainResumesIntoNewProcessingWindow
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    self.clock.now = 1003.0;
    [tracker _pollAtTime:self.clock.now];
    XCTAssertEqual(self.mockDelegate.hangCount, 1);

    // AfterWaiting (or any non-BeforeWaiting activity) also signals recovery
    // because the main thread visibly transitioned away from the hung state.
    self.clock.now = 1004.0;
    [tracker _simulateRunLoopActivity:kCFRunLoopAfterWaiting];
    XCTAssertEqual(self.mockDelegate.recoverCount, 1);
}

- (void)testRecovery_DoesNotFireWithoutPriorHang
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    [tracker _simulateRunLoopActivity:kCFRunLoopBeforeWaiting];

    XCTAssertEqual(self.mockDelegate.recoverCount, 0);
}

#pragma mark - Throttle

- (void)testThrottle_OnlyOneHangPerProcessingWindow
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    self.clock.now = 1003.0;
    [tracker _pollAtTime:self.clock.now];

    // Subsequent polls within the same processing window must not refire.
    self.clock.now = 1005.0;
    [tracker _pollAtTime:self.clock.now];
    self.clock.now = 1010.0;
    [tracker _pollAtTime:self.clock.now];

    XCTAssertEqual(self.mockDelegate.hangCount, 1);
}

- (void)testThrottle_NewWindowCanFireAgain
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    self.clock.now = 1003.0;
    [tracker _pollAtTime:self.clock.now];
    XCTAssertEqual(self.mockDelegate.hangCount, 1);

    // Recover, then start a new processing window from a fresh timestamp.
    [tracker _simulateRunLoopActivity:kCFRunLoopBeforeWaiting];
    self.clock.now = 1010.0;
    [tracker _simulateRunLoopActivity:kCFRunLoopAfterWaiting];

    self.clock.now = 1013.0;
    [tracker _pollAtTime:self.clock.now];
    XCTAssertEqual(self.mockDelegate.hangCount, 2);
}

#pragma mark - Suspension guard

- (void)testSuspensionGuard_ResetsAfterLargeOvershoot
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    // Seed the suspension-guard baseline with a normal first poll.
    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    self.clock.now = 1000.4;
    [tracker _pollAtTime:self.clock.now];

    // Now jump the clock far enough that the overshoot guard fires. Threshold=2.0
    // means suspensionOvershoot = 10.0; jump 60 seconds.
    self.clock.now = 1060.0;
    [tracker _pollAtTime:self.clock.now];

    // The guard should have reset processingStartWallClock to "now" and not
    // reported a hang despite the 60s elapsed since the runloop entered.
    XCTAssertEqual(self.mockDelegate.hangCount, 0);

    // A short additional poll right after should not retroactively fire either.
    self.clock.now = 1060.5;
    [tracker _pollAtTime:self.clock.now];
    XCTAssertEqual(self.mockDelegate.hangCount, 0);
}

- (void)testSuspensionGuard_FirstPollDoesNotResetState
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:2.0 debuggerAttached:NO appActive:YES];

    // The runloop entered at t=1000. The watchdog thread doesn't get scheduled
    // until t=1060 - a 60s gap that would falsely trip the suspension guard
    // if the guard ran on the first poll. The fix is to skip the guard on the
    // first poll so we still report the hang in progress.
    [tracker _simulateRunLoopActivity:kCFRunLoopEntry];
    self.clock.now = 1060.0;
    [tracker _pollAtTime:self.clock.now];

    XCTAssertEqual(self.mockDelegate.hangCount, 1);
    XCTAssertGreaterThan(self.mockDelegate.lastDuration, 50.0);
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
