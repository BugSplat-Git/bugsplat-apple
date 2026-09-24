//
//  BugSplatShouldSendCrashReportTests.m
//  BugSplatTests
//
//  Tests for -bugSplat:shouldSendCrashReport:, the pre-upload hook that lets an app
//  discard a crash or fatal hang report instead of sending it (issue #87).
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <TargetConditionals.h>
#import <XCTest/XCTest.h>

#import <BugSplat/BugSplat.h>

#import "BugSplat+Testing.h"
#import "BugSplatTestSupport.h"
#import "BugSplatUploadService.h"
#import "BugSplatUploadService+Testing.h"
#import "BugSplatTestCrashDirectory.h"
#import "MockCrashReporter.h"
#import "MockCrashStorage.h"
#import "MockUserDefaults.h"
#import "MockBundle.h"
#import "MockURLSession.h"

#pragma mark - Delegates

/// Answers the hook with a fixed verdict and records every BugSplatCrashInfo it is handed.
@interface DecidingDelegate : NSObject <BugSplatDelegate>
@property (nonatomic, assign) BOOL verdict;
@property (nonatomic, strong) NSMutableArray<BugSplatCrashInfo *> *received;
@property (nonatomic, assign) BOOL willShowAlertInvoked;
@property (nonatomic, assign) BOOL willSendInvoked;
@end

@implementation DecidingDelegate

- (instancetype)init
{
    if ((self = [super init])) {
        _verdict = NO;
        _received = [NSMutableArray array];
    }
    return self;
}

- (BOOL)bugSplat:(BugSplat *)bugSplat shouldSendCrashReport:(BugSplatCrashInfo *)crashInfo
{
    [self.received addObject:crashInfo];
    return self.verdict;
}

- (void)bugSplatWillShowSubmitCrashReportAlert:(BugSplat *)bugSplat
{
    self.willShowAlertInvoked = YES;
}

- (void)bugSplatWillSendCrashReport:(BugSplat *)bugSplat sessionID:(nullable NSUUID *)sessionID
{
    self.willSendInvoked = YES;
}

@end

/// Raises from the hook, to pin down what a buggy delegate does.
@interface ThrowingDelegate : NSObject <BugSplatDelegate>
@end

@implementation ThrowingDelegate

- (BOOL)bugSplat:(BugSplat *)bugSplat shouldSendCrashReport:(BugSplatCrashInfo *)crashInfo
{
    [NSException raise:@"DelegateBug" format:@"something went wrong in the host app"];
    return NO;
}

@end

/// Implements no hook at all - the pre-existing behaviour must be untouched.
@interface NoHookDelegate : NSObject <BugSplatDelegate>
@property (nonatomic, assign) BOOL willSendInvoked;
@end

@implementation NoHookDelegate

- (void)bugSplatWillSendCrashReport:(BugSplat *)bugSplat sessionID:(nullable NSUUID *)sessionID
{
    self.willSendInvoked = YES;
}

@end

#pragma mark - Tests

@interface BugSplatShouldSendCrashReportTests : XCTestCase

@property (nonatomic, strong) BugSplat *bugSplat;
@property (nonatomic, strong) MockCrashReporter *mockCrashReporter;
@property (nonatomic, strong) MockCrashStorage *mockCrashStorage;
@property (nonatomic, strong) MockUserDefaults *mockUserDefaults;
@property (nonatomic, strong) MockBundle *mockBundle;
@property (nonatomic, strong) MockURLSession *mockSession;
@property (nonatomic, copy) NSString *isolatedCrashesDirectory;

@end

@implementation BugSplatShouldSendCrashReportTests

- (void)setUp
{
    [super setUp];

    self.mockCrashReporter = [[MockCrashReporter alloc] init];
    self.mockCrashStorage = [[MockCrashStorage alloc] init];
    self.mockUserDefaults = [[MockUserDefaults alloc] init];
    self.mockBundle = [[MockBundle alloc] init];

    [self.mockBundle setObject:@"TestApp" forInfoDictionaryKey:@"CFBundleName"];
    [self.mockBundle setObject:@"1.0.0" forInfoDictionaryKey:@"CFBundleShortVersionString"];
    [self.mockBundle setObject:@"testdb" forInfoDictionaryKey:@"BugSplatDatabase"];

    self.bugSplat = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                               crashStorage:self.mockCrashStorage
                                               userDefaults:self.mockUserDefaults
                                                     bundle:self.mockBundle];

    self.isolatedCrashesDirectory = BugSplatTestsMakeIsolatedCrashesDirectory();
    [self.bugSplat setCrashesDirectoryPathOverride:self.isolatedCrashesDirectory];

    // An upload service wired to a mock session, so "did anything go out?" is just a
    // request count. Responses are queued per-test; with none queued a request still
    // registers, which is what the no-network assertions rely on.
    self.mockSession = [[MockURLSession alloc] init];
    BugSplatUploadService *uploadService = [[BugSplatUploadService alloc] initWithDatabase:@"testdb"
                                                                           applicationName:@"TestApp"
                                                                        applicationVersion:@"1.0.0"
                                                                                urlSession:self.mockSession];
    [uploadService setCompletionDispatcher:^(dispatch_block_t block) { block(); }];
    [self.bugSplat setUploadServiceForTesting:uploadService];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.isolatedCrashesDirectory error:nil];
    self.isolatedCrashesDirectory = nil;

    [self.mockCrashReporter reset];
    [self.mockCrashStorage reset];
    [self.mockUserDefaults reset];
    self.bugSplat = nil;
    self.mockSession = nil;

    [super tearDown];
}

#pragma mark - Helpers

/// Plants a crash + meta pair as if it had been persisted at a previous launch.
- (void)plantReportNamed:(NSString *)filename extraMetadata:(nullable NSDictionary *)extra
{
    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *crashPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"crash"];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];

    XCTAssertTrue([[@"test crash report" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:crashPath atomically:YES]);

    NSMutableDictionary *meta = [@{
        @"database": @"testdb",
        @"applicationName": @"TestApp",
        @"applicationVersion": @"1.0.0",
        @"timestamp": @"2026-06-11T00:00:00Z",
    } mutableCopy];
    [meta addEntriesFromDictionary:extra ?: @{}];

    XCTAssertTrue([meta writeToFile:metaPath atomically:YES]);
}

- (BOOL)reportExistsNamed:(NSString *)filename
{
    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *crashPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"crash"];
    return [[NSFileManager defaultManager] fileExistsAtPath:crashPath];
}

/// Queues a full presign -> S3 -> commit success flow.
- (void)queueSuccessfulUpload
{
    NSData *presignJSON = [@"{\"url\":\"https://example.com/presigned\"}" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *commitJSON = [@"{\"crashId\":123,\"infoUrl\":\"https://example.com/crash/123\"}" dataUsingEncoding:NSUTF8StringEncoding];
    [self.mockSession queueResponseWithData:presignJSON response:[MockURLSession jsonResponseWithStatusCode:200] error:nil];
    [self.mockSession queueResponseWithData:nil response:[MockURLSession responseWithStatusCode:200] error:nil];
    [self.mockSession queueResponseWithData:commitJSON response:[MockURLSession jsonResponseWithStatusCode:200] error:nil];
}

#pragma mark - Returning NO

- (void)testReturningNO_UploadsNothing
{
    [self plantReportNamed:@"99999999991" extraMetadata:nil];

    DecidingDelegate *delegate = [[DecidingDelegate alloc] init];
    delegate.verdict = NO;
    self.bugSplat.delegate = delegate;
    self.bugSplat.autoSubmitCrashReport = YES;

    [self.bugSplat processPendingCrashReports];

    XCTAssertEqual(delegate.received.count, 1, @"the hook should be consulted for the planted report");
    XCTAssertEqual(self.mockSession.requestCount, 0, @"declining a report must make no network request at all");
    XCTAssertFalse(delegate.willSendInvoked, @"willSend belongs to the send path and must not fire for a declined report");
}

- (void)testReturningNO_ShowsNoDialogOrAlert
{
    [self plantReportNamed:@"99999999992" extraMetadata:nil];

    DecidingDelegate *delegate = [[DecidingDelegate alloc] init];
    delegate.verdict = NO;
    self.bugSplat.delegate = delegate;

    // autoSubmit NO is the configuration that would otherwise put up the crash dialog on
    // macOS and the Send / Don't Send alert on iOS. The hook has to pre-empt both.
    self.bugSplat.autoSubmitCrashReport = NO;

    [self.bugSplat processPendingCrashReports];

    XCTAssertEqual(delegate.received.count, 1);
    XCTAssertFalse(delegate.willShowAlertInvoked, @"no crash dialog or alert may be presented for a declined report");
    XCTAssertEqual(self.mockSession.requestCount, 0);
}

- (void)testReturningNO_DeletesTheReportFromDisk
{
    [self plantReportNamed:@"99999999993" extraMetadata:nil];
    XCTAssertTrue([self reportExistsNamed:@"99999999993"]);

    DecidingDelegate *delegate = [[DecidingDelegate alloc] init];
    delegate.verdict = NO;
    self.bugSplat.delegate = delegate;
    self.bugSplat.autoSubmitCrashReport = YES;

    [self.bugSplat processPendingCrashReports];

    XCTAssertFalse([self reportExistsNamed:@"99999999993"],
                   @"a declined report must be removed so it does not come back next launch");
}

- (void)testReturningNO_OverridesUserSubmitted
{
    // This report is already marked to skip the dialog - either the user agreed to send it
    // and the upload failed, or it was auto-submitted (fatal hangs are, by default). The hook
    // sits ahead of that check, so it can still discard the report.
    [self plantReportNamed:@"99999999994" extraMetadata:@{ @"userSubmitted": @YES }];

    DecidingDelegate *delegate = [[DecidingDelegate alloc] init];
    delegate.verdict = NO;
    self.bugSplat.delegate = delegate;

    [self.bugSplat processPendingCrashReports];

    XCTAssertEqual(delegate.received.count, 1);
    XCTAssertTrue(delegate.received.firstObject.userSubmitted,
                  @"crashInfo must surface userSubmitted so an app can let that prior decision win");
    XCTAssertEqual(self.mockSession.requestCount, 0, @"returning NO wins over userSubmitted");
    XCTAssertFalse([self reportExistsNamed:@"99999999994"]);
}

#pragma mark - Draining

- (void)testReturningNO_ConsultedOncePerPendingReportAndDrainsAllOfThem
{
    [self plantReportNamed:@"99999999995" extraMetadata:nil];
    [self plantReportNamed:@"99999999996" extraMetadata:nil];
    [self plantReportNamed:@"99999999997" extraMetadata:nil];

    DecidingDelegate *delegate = [[DecidingDelegate alloc] init];
    delegate.verdict = NO;
    self.bugSplat.delegate = delegate;
    self.bugSplat.autoSubmitCrashReport = YES;

    [self.bugSplat processPendingCrashReports];

    XCTAssertEqual(delegate.received.count, 3,
                   @"every pending report should be offered, not just the newest - otherwise "
                   @"declined reports block the ones behind them");
    XCTAssertEqual(self.mockSession.requestCount, 0);
    XCTAssertFalse([self reportExistsNamed:@"99999999995"]);
    XCTAssertFalse([self reportExistsNamed:@"99999999996"]);
    XCTAssertFalse([self reportExistsNamed:@"99999999997"]);
}

#pragma mark - Retries

- (void)testFailedUploadIsOfferedAgainOnTheNextPass
{
    [self plantReportNamed:@"99999999998" extraMetadata:nil];

    DecidingDelegate *delegate = [[DecidingDelegate alloc] init];
    delegate.verdict = YES;
    self.bugSplat.delegate = delegate;
    self.bugSplat.autoSubmitCrashReport = YES;

    // First pass: allowed through, but the upload fails, so the report stays on disk.
    self.mockSession.nextError = [NSError errorWithDomain:NSURLErrorDomain
                                                     code:NSURLErrorNotConnectedToInternet
                                                 userInfo:nil];
    [self.bugSplat processPendingCrashReports];

    XCTAssertEqual(delegate.received.count, 1);
    XCTAssertTrue([self reportExistsNamed:@"99999999998"], @"a failed upload must leave the report for a retry");

    // Second pass, as if the app had been relaunched - this time the app says no.
    delegate.verdict = NO;
    self.mockSession.nextError = nil;
    NSUInteger requestsAfterFirstPass = self.mockSession.requestCount;
    [self.bugSplat processPendingCrashReports];

    XCTAssertEqual(delegate.received.count, 2,
                   @"the hook is consulted once per delivery attempt, so a retried report is asked about again");
    XCTAssertEqual(self.mockSession.requestCount, requestsAfterFirstPass,
                   @"declining on the retry must not send anything further");
    XCTAssertFalse([self reportExistsNamed:@"99999999998"], @"declining on the retry discards the report");
}

#pragma mark - crashInfo contents

- (void)testCrashInfoCarriesSessionDateAndApplicationDetails
{
    NSUUID *crashedSessionID = [NSUUID UUID];
    [self plantReportNamed:@"99999999981" extraMetadata:@{ @"sessionID": crashedSessionID.UUIDString }];

    DecidingDelegate *delegate = [[DecidingDelegate alloc] init];
    delegate.verdict = NO;
    self.bugSplat.delegate = delegate;

    [self.bugSplat processPendingCrashReports];

    BugSplatCrashInfo *info = delegate.received.firstObject;
    XCTAssertNotNil(info);
    XCTAssertEqual(info.type, BugSplatCrashInfoTypeCrash);
    XCTAssertEqualObjects(info.sessionID, crashedSessionID,
                          @"sessionID ties the report back to whatever the app recorded for that session");
    XCTAssertEqualObjects(info.applicationName, @"TestApp");
    XCTAssertEqualObjects(info.applicationVersion, @"1.0.0");
    XCTAssertNotNil(info.crashDate, @"the persisted timestamp should be surfaced as a date");
    XCTAssertFalse(info.userSubmitted);
}

- (void)testCrashInfoReportsFatalHangForHangReports
{
    // Hang reports are distinguished by the -hang filename suffix, which is how the rest
    // of the pipeline tells them apart from crashes.
    [self plantReportNamed:@"99999999982-hang" extraMetadata:nil];

    DecidingDelegate *delegate = [[DecidingDelegate alloc] init];
    delegate.verdict = NO;
    self.bugSplat.delegate = delegate;

    [self.bugSplat processPendingCrashReports];

    XCTAssertEqual(delegate.received.count, 1, @"fatal hang reports go through the same hook");
    XCTAssertEqual(delegate.received.firstObject.type, BugSplatCrashInfoTypeFatalHang);
    XCTAssertEqual(self.mockSession.requestCount, 0);
    XCTAssertFalse([self reportExistsNamed:@"99999999982-hang"]);
}

- (void)testCrashInfoToleratesMissingMetadata
{
    // A .crash with no .meta beside it: everything optional should come back nil rather
    // than crashing the host app inside its own delegate callback.
    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *crashPath = [[dir stringByAppendingPathComponent:@"99999999983"] stringByAppendingPathExtension:@"crash"];
    XCTAssertTrue([[@"test crash report" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:crashPath atomically:YES]);

    DecidingDelegate *delegate = [[DecidingDelegate alloc] init];
    delegate.verdict = NO;
    self.bugSplat.delegate = delegate;

    [self.bugSplat processPendingCrashReports];

    BugSplatCrashInfo *info = delegate.received.firstObject;
    XCTAssertNotNil(info, @"the hook should still be offered a report with unreadable metadata");
    XCTAssertNil(info.sessionID);
    XCTAssertNil(info.crashDate);
    XCTAssertNil(info.applicationName);
    XCTAssertFalse(info.userSubmitted);
}

#pragma mark - Default behaviour

- (void)testNotImplementingTheHookStillUploads
{
    [self plantReportNamed:@"99999999984" extraMetadata:nil];
    [self queueSuccessfulUpload];

    NoHookDelegate *delegate = [[NoHookDelegate alloc] init];
    self.bugSplat.delegate = delegate;
    self.bugSplat.autoSubmitCrashReport = YES;

    [self.bugSplat processPendingCrashReports];

    XCTAssertTrue(delegate.willSendInvoked, @"apps that never adopt the hook must be unaffected");
    XCTAssertGreaterThan(self.mockSession.requestCount, 0);
}

- (void)testNoDelegateAtAllStillUploads
{
    [self plantReportNamed:@"99999999985" extraMetadata:nil];
    [self queueSuccessfulUpload];

    self.bugSplat.delegate = nil;
    self.bugSplat.autoSubmitCrashReport = YES;

    [self.bugSplat processPendingCrashReports];

    XCTAssertGreaterThan(self.mockSession.requestCount, 0, @"a nil delegate means send, as before");
}

- (void)testReturningYESUploadsAsUsual
{
    [self plantReportNamed:@"99999999986" extraMetadata:nil];
    [self queueSuccessfulUpload];

    DecidingDelegate *delegate = [[DecidingDelegate alloc] init];
    delegate.verdict = YES;
    self.bugSplat.delegate = delegate;
    self.bugSplat.autoSubmitCrashReport = YES;

    [self.bugSplat processPendingCrashReports];

    XCTAssertEqual(delegate.received.count, 1);
    XCTAssertTrue(delegate.willSendInvoked);
    XCTAssertGreaterThan(self.mockSession.requestCount, 0);
    XCTAssertFalse([self reportExistsNamed:@"99999999986"], @"a successful upload cleans the report up");
}

- (void)testThrowingDelegateSendsTheReport
{
    // An exception is indistinguishable from an unimplemented method, and the established
    // default is to send - so a buggy delegate must not silently start dropping reports.
    [self plantReportNamed:@"99999999987" extraMetadata:nil];
    [self queueSuccessfulUpload];

    ThrowingDelegate *delegate = [[ThrowingDelegate alloc] init];
    self.bugSplat.delegate = delegate;
    self.bugSplat.autoSubmitCrashReport = YES;

    XCTAssertNoThrow([self.bugSplat processPendingCrashReports],
                     @"an exception from the host app's delegate must not escape into BugSplat");
    XCTAssertGreaterThan(self.mockSession.requestCount, 0);
}

@end
