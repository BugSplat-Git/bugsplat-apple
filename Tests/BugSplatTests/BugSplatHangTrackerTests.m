//
//  BugSplatHangTrackerTests.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "BugSplatHangTracker.h"


@interface MockHangTrackerDelegate : NSObject <BugSplatHangTrackerDelegate>
@property (atomic, assign) NSInteger hangCount;
@property (atomic, assign) NSInteger recoverCount;
@property (atomic, assign) NSTimeInterval lastDuration;
@property (atomic, copy, nullable) NSString *lastAppState;
@property (atomic, strong, nullable) XCTestExpectation *hangExpectation;
@property (atomic, strong, nullable) XCTestExpectation *recoverExpectation;
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
    [self.recoverExpectation fulfill];
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
    return [[BugSplatHangTracker alloc] initWithThresholdSeconds:threshold
                                                        delegate:self.mockDelegate
                                          isDebuggerAttachedBlock:^BOOL { return debuggerAttached; }
                                                isAppActiveBlock:^BOOL { return appActive; }];
}

/// Runs the main runloop for `seconds` so the CFRunLoopObserver gets a chance to fire.
- (void)pumpMainRunLoopForSeconds:(NSTimeInterval)seconds
{
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
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

#pragma mark - Start / stop

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

#pragma mark - Detection

- (void)testDetectsHang_WhenMainThreadSleepsPastThreshold
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:0.2 debuggerAttached:NO appActive:YES];
    self.mockDelegate.hangExpectation = [self expectationWithDescription:@"hang detected"];

    [tracker start];

    // Pump the runloop briefly so the observer fires an AfterWaiting event,
    // establishing a "processing start" timestamp for the next block of work.
    [self pumpMainRunLoopForSeconds:0.1];

    // Block the main thread past the threshold.
    [NSThread sleepForTimeInterval:0.6];

    // Give the watchdog thread time to finish and dispatch.
    [self waitForExpectations:@[self.mockDelegate.hangExpectation] timeout:1.0];

    XCTAssertEqual(self.mockDelegate.hangCount, 1);
    XCTAssertGreaterThan(self.mockDelegate.lastDuration, 0.2);
    XCTAssertEqualObjects(self.mockDelegate.lastAppState, @"active");

    [tracker stop];
}

- (void)testDoesNotDetectHang_WhenDebuggerAttached
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:0.2 debuggerAttached:YES appActive:YES];

    [tracker start];
    [self pumpMainRunLoopForSeconds:0.1];
    [NSThread sleepForTimeInterval:0.6];
    [self pumpMainRunLoopForSeconds:0.3];

    XCTAssertEqual(self.mockDelegate.hangCount, 0);
    [tracker stop];
}

- (void)testDoesNotDetectHang_WhenAppInactive
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:0.2 debuggerAttached:NO appActive:NO];

    [tracker start];
    [self pumpMainRunLoopForSeconds:0.1];
    [NSThread sleepForTimeInterval:0.6];
    [self pumpMainRunLoopForSeconds:0.3];

    XCTAssertEqual(self.mockDelegate.hangCount, 0);
    [tracker stop];
}

#pragma mark - Recovery

- (void)testRecovery_FiresAfterMainResumesFromHang
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:0.2 debuggerAttached:NO appActive:YES];
    self.mockDelegate.hangExpectation = [self expectationWithDescription:@"hang detected"];
    self.mockDelegate.recoverExpectation = [self expectationWithDescription:@"recovery"];

    [tracker start];
    [self pumpMainRunLoopForSeconds:0.1];

    [NSThread sleepForTimeInterval:0.5];

    [self waitForExpectations:@[self.mockDelegate.hangExpectation] timeout:1.0];

    // Resume processing so the observer hits BeforeWaiting and we emit recovery.
    [self pumpMainRunLoopForSeconds:0.3];

    [self waitForExpectations:@[self.mockDelegate.recoverExpectation] timeout:1.0];

    XCTAssertEqual(self.mockDelegate.hangCount, 1);
    XCTAssertEqual(self.mockDelegate.recoverCount, 1);

    [tracker stop];
}

#pragma mark - Throttle

- (void)testThrottle_OnlyOneHangPerProcessingWindow
{
    BugSplatHangTracker *tracker = [self trackerWithThreshold:0.2 debuggerAttached:NO appActive:YES];
    self.mockDelegate.hangExpectation = [self expectationWithDescription:@"hang detected"];

    [tracker start];
    [self pumpMainRunLoopForSeconds:0.1];

    // One long block - should produce exactly one hang event even though the watchdog
    // polls multiple times inside it.
    [NSThread sleepForTimeInterval:1.5];

    [self waitForExpectations:@[self.mockDelegate.hangExpectation] timeout:1.0];

    // Wait briefly to ensure no additional reports sneak in from the same window.
    [self pumpMainRunLoopForSeconds:0.2];

    XCTAssertEqual(self.mockDelegate.hangCount, 1);

    [tracker stop];
}

@end
