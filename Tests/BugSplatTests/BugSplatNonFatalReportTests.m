//
//  BugSplatNonFatalReportTests.m
//  BugSplatTests
//
//  Tests for posting a stack trace for a non-crash event - the -postException:,
//  -postError:, and -postExceptionWithName:reason: APIs. This is the Apple counterpart to
//  BugSplat::CreateXmlReport in the Windows SDK.
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
#import "MockBundle.h"
#import "MockCrashReporter.h"
#import "MockCrashStorage.h"
#import "MockURLSession.h"
#import "MockUserDefaults.h"

/// A crash reporter that deliberately does NOT implement the optional live-report selector,
/// so the "this reporter cannot capture live reports" branch can be exercised.
@interface NonCapturingCrashReporter : NSObject <BugSplatCrashReporterProtocol>
@property (nonatomic, strong, nullable) NSData *customData;
@end

@implementation NonCapturingCrashReporter
- (BOOL)hasPendingCrashReport { return NO; }
- (NSData *)loadPendingCrashReportDataAndReturnError:(NSError **)outError { return nil; }
- (void)purgePendingCrashReport {}
- (BOOL)enableCrashReporterAndReturnError:(NSError **)outError { return YES; }
@end


@interface BugSplatNonFatalReportTests : XCTestCase

@property (nonatomic, strong) BugSplat *bugSplat;
@property (nonatomic, strong) MockCrashReporter *mockCrashReporter;
@property (nonatomic, strong) MockCrashStorage *mockCrashStorage;
@property (nonatomic, strong) MockUserDefaults *mockUserDefaults;
@property (nonatomic, strong) MockBundle *mockBundle;
@property (nonatomic, strong) MockURLSession *mockSession;

@end

@implementation BugSplatNonFatalReportTests

- (void)setUp
{
    [super setUp];

    self.mockCrashReporter = [[MockCrashReporter alloc] init];
    self.mockCrashStorage = [[MockCrashStorage alloc] init];
    self.mockUserDefaults = [[MockUserDefaults alloc] init];
    self.mockBundle = [[MockBundle alloc] init];
    self.mockSession = [[MockURLSession alloc] init];

    [self.mockBundle setObject:@"TestApp" forInfoDictionaryKey:@"CFBundleName"];
    [self.mockBundle setObject:@"1.0.0" forInfoDictionaryKey:@"CFBundleShortVersionString"];
    [self.mockBundle setObject:@"testdb" forInfoDictionaryKey:@"BugSplatDatabase"];

    self.bugSplat = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                               crashStorage:self.mockCrashStorage
                                               userDefaults:self.mockUserDefaults
                                                     bundle:self.mockBundle];

    // Real live-report data so the report parses and text-formats like it would in production.
    self.mockCrashReporter.liveReportData =
        [MockCrashReporter liveReportDataWithException:[NSException exceptionWithName:@"Seed"
                                                                               reason:@"seed"
                                                                             userInfo:nil]];
    XCTAssertNotNil(self.mockCrashReporter.liveReportData, @"Could not seed live-report data");
}

- (void)tearDown
{
    [self.mockCrashReporter reset];
    [self.mockCrashStorage reset];
    [self.mockUserDefaults reset];
    [self.mockSession reset];
    self.bugSplat = nil;

    [super tearDown];
}

#pragma mark - Helpers

/// Injects an upload service backed by the mock session. Its presence is also what marks the
/// instance as "started" for the non-fatal APIs, so tests of the not-started path skip this.
- (void)installUploadService
{
    BugSplatUploadService *service = [[BugSplatUploadService alloc] initWithDatabase:@"testdb"
                                                                    applicationName:@"TestApp"
                                                                 applicationVersion:@"1.0.0"
                                                                         urlSession:self.mockSession];
    // Same synchronous dispatcher the upload service tests use, so the three-step flow does
    // not depend on the run loop draining queued main-queue blocks.
    [service setCompletionDispatcher:^(dispatch_block_t block) {
        if ([NSThread isMainThread]) {
            block();
        } else {
            dispatch_sync(dispatch_get_main_queue(), block);
        }
    }];
    [self.bugSplat setUploadServiceForTesting:service];
}

/// Queues the three responses of the presigned-URL upload flow.
- (void)queueSuccessfulUploadFlowWithCommitBody:(NSDictionary *)commitBody
{
    NSData *presignedData = [NSJSONSerialization dataWithJSONObject:@{@"url": @"https://s3.example.com/key?sig=abc"}
                                                            options:0
                                                              error:nil];
    [self.mockSession queueResponseWithData:presignedData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:200]
                                      error:nil];
    NSData *commitData = [NSJSONSerialization dataWithJSONObject:commitBody ?: @{} options:0 error:nil];
    [self.mockSession queueResponseWithData:commitData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
}

- (void)queueSuccessfulUploadFlow
{
    [self queueSuccessfulUploadFlowWithCommitBody:@{@"status": @"success"}];
}

/// The multipart body of the commit request (the third and last request in the flow).
- (NSString *)commitRequestBody
{
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)3, @"Expected the full 3-step upload flow");
    MockURLSessionRequest *commitRequest = self.mockSession.recordedRequests[2];
    return [[NSString alloc] initWithData:commitRequest.request.HTTPBody encoding:NSUTF8StringEncoding];
}

/// The `attributes` form field of the commit request, decoded back into a dictionary.
- (NSDictionary<NSString *, NSString *> *)commitRequestAttributes
{
    NSString *body = [self commitRequestBody];
    NSRange fieldRange = [body rangeOfString:@"name=\"attributes\"\r\n\r\n"];
    XCTAssertNotEqual(fieldRange.location, NSNotFound, @"Commit body carried no attributes field");

    NSUInteger start = NSMaxRange(fieldRange);
    NSRange terminator = [body rangeOfString:@"\r\n--" options:0 range:NSMakeRange(start, body.length - start)];
    XCTAssertNotEqual(terminator.location, NSNotFound, @"Attributes field was not terminated");

    NSString *json = [body substringWithRange:NSMakeRange(start, terminator.location - start)];
    NSError *error = nil;
    NSDictionary *attributes = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                                               options:0
                                                                 error:&error];
    XCTAssertNotNil(attributes, @"Attributes were not valid JSON: %@", error);
    return attributes;
}

#pragma mark - Happy path

- (void)testPostException_UploadsThroughTheStandardFlow
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    __block BugSplatReportResult *received = nil;
    __block NSError *receivedError = nil;

    NSException *exception = [NSException exceptionWithName:@"NSRangeException"
                                                     reason:@"index 99 beyond bounds"
                                                   userInfo:nil];
    [self.bugSplat postException:exception completion:^(BugSplatReportResult *result, NSError *error) {
        received = result;
        receivedError = error;
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertNil(receivedError);
    XCTAssertNotNil(received);
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)3);
    XCTAssertEqual(self.mockCrashReporter.liveReportCallCount, (NSUInteger)1);
}

- (void)testPostException_ReturnsCrashIdAndInfoUrl
{
    [self installUploadService];
    [self queueSuccessfulUploadFlowWithCommitBody:@{@"crashId": @4242,
                                                    @"infoUrl": @"https://app.bugsplat.com/v2/crash?id=4242"}];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    __block BugSplatReportResult *received = nil;

    [self.bugSplat postExceptionWithName:@"ImageDecodeFailure"
                                  reason:@"unsupported pixel format"
                              attributes:nil
                             attachments:nil
                              completion:^(BugSplatReportResult *result, NSError *error) {
        received = result;
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertEqualObjects(received.crashId, @4242);
    XCTAssertEqualObjects(received.infoUrl, @"https://app.bugsplat.com/v2/crash?id=4242");
}

- (void)testPostException_ForwardsTheExceptionToTheCrashReporter
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    NSException *exception = [NSException exceptionWithName:@"NSRangeException"
                                                     reason:@"index 99 beyond bounds"
                                                   userInfo:nil];

    [self.bugSplat postException:exception completion:^(BugSplatReportResult *result, NSError *error) {
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // The caller's own exception is handed to PLCrashReporter so a raised exception's
    // callStackReturnAddresses land in the report as the last exception backtrace.
    XCTAssertEqual(self.mockCrashReporter.lastLiveReportException, exception);
}

- (void)testPostException_UploadsAsThePlatformCrashTypeSoItSymbolicates
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postException:[NSException exceptionWithName:@"Boom" reason:@"bang" userInfo:nil]
                      completion:^(BugSplatReportResult *result, NSError *error) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    NSString *body = [self commitRequestBody];
#if TARGET_OS_OSX
    XCTAssertTrue([body containsString:@"\r\n\r\nmacOS\r\n"], @"Expected crashType macOS, got:\n%@", body);
    XCTAssertTrue([body containsString:@"\r\n\r\n13\r\n"], @"Expected crashTypeId 13, got:\n%@", body);
#else
    XCTAssertTrue([body containsString:@"\r\n\r\niOS\r\n"], @"Expected crashType iOS, got:\n%@", body);
    XCTAssertTrue([body containsString:@"\r\n\r\n26\r\n"], @"Expected crashTypeId 26, got:\n%@", body);
#endif
    // Never the feedback type - these reports need to symbolicate against the app's dSYMs.
    XCTAssertFalse([body containsString:@"User.Feedback"]);
}

- (void)testPostException_SendsTheReasonAsTheReportDescription
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postException:[NSException exceptionWithName:@"Boom" reason:@"the widget exploded" userInfo:nil]
                      completion:^(BugSplatReportResult *result, NSError *error) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertTrue([[self commitRequestBody] containsString:@"the widget exploded"]);
}

#pragma mark - Attributes

- (void)testPostException_StampsTheNonFatalMarkerAttributes
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postException:[NSException exceptionWithName:@"NSRangeException" reason:@"oops" userInfo:nil]
                      completion:^(BugSplatReportResult *result, NSError *error) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    NSDictionary *attributes = [self commitRequestAttributes];
    XCTAssertEqualObjects(attributes[@"bugsplat-nonfatal"], @"true");
    XCTAssertEqualObjects(attributes[@"bugsplat-nonfatal-name"], @"NSRangeException");
    XCTAssertNotNil(attributes[@"bugsplat-nonfatal-captured-at"]);
}

- (void)testPostException_MergesSessionAndCallerAttributes
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    [self.bugSplat setValue:@"main" forAttribute:@"branch"];
    [self.bugSplat setValue:@"session" forAttribute:@"scope"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postException:[NSException exceptionWithName:@"Boom" reason:nil userInfo:nil]
                      attributes:@{@"scope": @"call", @"screen": @"Checkout"}
                     attachments:nil
                      completion:^(BugSplatReportResult *result, NSError *error) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    NSDictionary *attributes = [self commitRequestAttributes];
    XCTAssertEqualObjects(attributes[@"branch"], @"main", @"Session attributes should be included");
    XCTAssertEqualObjects(attributes[@"screen"], @"Checkout", @"Call attributes should be included");
    XCTAssertEqualObjects(attributes[@"scope"], @"call", @"Call attributes should win over session attributes");
}

- (void)testPostException_CallerCannotOverrideTheNonFatalMarker
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postException:[NSException exceptionWithName:@"Boom" reason:nil userInfo:nil]
                      attributes:@{@"bugsplat-nonfatal": @"false", @"bugsplat-nonfatal-name": @"spoofed"}
                     attachments:nil
                      completion:^(BugSplatReportResult *result, NSError *error) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // A dashboard filter on bugsplat-nonfatal has to be trustworthy, so the SDK's values win.
    NSDictionary *attributes = [self commitRequestAttributes];
    XCTAssertEqualObjects(attributes[@"bugsplat-nonfatal"], @"true");
    XCTAssertEqualObjects(attributes[@"bugsplat-nonfatal-name"], @"Boom");
}

#pragma mark - postError

- (void)testPostError_UsesTheDomainAsTheNameAndSendsDomainAndCode
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    NSError *error = [NSError errorWithDomain:@"com.example.sync"
                                         code:42
                                     userInfo:@{NSLocalizedDescriptionKey: @"Sync failed"}];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postError:error completion:^(BugSplatReportResult *result, NSError *postError) {
        XCTAssertNil(postError);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    NSDictionary *attributes = [self commitRequestAttributes];
    // Grouped by domain, not domain+code: the stack is what separates one failure from another.
    XCTAssertEqualObjects(attributes[@"bugsplat-nonfatal-name"], @"com.example.sync");
    XCTAssertEqualObjects(attributes[@"bugsplat-nonfatal-error-domain"], @"com.example.sync");
    XCTAssertEqualObjects(attributes[@"bugsplat-nonfatal-error-code"], @"42");

    XCTAssertEqualObjects(self.mockCrashReporter.lastLiveReportException.name, @"com.example.sync");
    XCTAssertEqualObjects(self.mockCrashReporter.lastLiveReportException.reason, @"Sync failed");
}

- (void)testPostError_EmptyDomain_StampsTheSameFallbackAsTheReportName
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    NSError *error = [NSError errorWithDomain:@"" code:5 userInfo:nil];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postError:error completion:^(BugSplatReportResult *result, NSError *postError) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // An empty domain attribute would identify nothing, and would not match a search for the
    // name the report was actually filed under.
    NSDictionary *attributes = [self commitRequestAttributes];
    XCTAssertEqualObjects(attributes[@"bugsplat-nonfatal-name"], @"NSError");
    XCTAssertEqualObjects(attributes[@"bugsplat-nonfatal-error-domain"], @"NSError");
    XCTAssertEqualObjects(attributes[@"bugsplat-nonfatal-error-code"], @"5");
}

- (void)testPostError_ErrorAttributesCannotBeOverriddenByCaller
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    NSError *error = [NSError errorWithDomain:@"com.example.sync" code:7 userInfo:nil];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postError:error
                  attributes:@{@"bugsplat-nonfatal-error-code": @"999"}
                 attachments:nil
                  completion:^(BugSplatReportResult *result, NSError *postError) {
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertEqualObjects([self commitRequestAttributes][@"bugsplat-nonfatal-error-code"], @"7");
}

#pragma mark - Validation and failure paths

- (void)testPostException_NilException_FailsWithoutCapturingOrUploading
{
    [self installUploadService];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    __block NSError *received = nil;

    [self.bugSplat postException:nil completion:^(BugSplatReportResult *result, NSError *error) {
        XCTAssertNil(result);
        received = error;
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertNotNil(received);
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)0);
    XCTAssertEqual(self.mockCrashReporter.liveReportCallCount, (NSUInteger)0);
}

- (void)testPostError_NilError_Fails
{
    [self installUploadService];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postError:nil completion:^(BugSplatReportResult *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)0);
}

- (void)testPostExceptionWithName_EmptyName_Fails
{
    [self installUploadService];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postExceptionWithName:@""
                                  reason:@"whatever"
                              attributes:nil
                             attachments:nil
                              completion:^(BugSplatReportResult *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertEqual(self.mockCrashReporter.liveReportCallCount, (NSUInteger)0);
}

- (void)testPostException_BeforeStart_FailsWithoutCapturing
{
    // No upload service installed - the instance has not been started.
    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    __block NSError *received = nil;

    [self.bugSplat postException:[NSException exceptionWithName:@"Boom" reason:nil userInfo:nil]
                      completion:^(BugSplatReportResult *result, NSError *error) {
        received = error;
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertNotNil(received);
    XCTAssertTrue([received.localizedDescription containsString:@"start"],
                  @"Error should point the caller at -start, got: %@", received.localizedDescription);
    XCTAssertEqual(self.mockCrashReporter.liveReportCallCount, (NSUInteger)0);
}

- (void)testPostException_ReporterWithoutLiveReportSupport_Fails
{
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:[[NonCapturingCrashReporter alloc] init]
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    BugSplatUploadService *service = [[BugSplatUploadService alloc] initWithDatabase:@"testdb"
                                                                    applicationName:@"TestApp"
                                                                 applicationVersion:@"1.0.0"
                                                                         urlSession:self.mockSession];
    [instance setUploadServiceForTesting:service];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [instance postException:[NSException exceptionWithName:@"Boom" reason:nil userInfo:nil]
                 completion:^(BugSplatReportResult *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)0);
}

- (void)testPostException_CaptureFailure_ReportsErrorWithoutUploading
{
    [self installUploadService];
    self.mockCrashReporter.liveReportError = [NSError errorWithDomain:@"PLCrashReporter"
                                                                 code:1
                                                             userInfo:@{NSLocalizedDescriptionKey: @"no temp dir"}];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    __block NSError *received = nil;

    [self.bugSplat postException:[NSException exceptionWithName:@"Boom" reason:nil userInfo:nil]
                      completion:^(BugSplatReportResult *result, NSError *error) {
        XCTAssertNil(result);
        received = error;
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertNotNil(received);
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)0);
}

- (void)testPostException_UnparseableReport_ReportsErrorWithoutUploading
{
    [self installUploadService];
    self.mockCrashReporter.liveReportData = [@"not a crash report" dataUsingEncoding:NSUTF8StringEncoding];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    [self.bugSplat postException:[NSException exceptionWithName:@"Boom" reason:nil userInfo:nil]
                      completion:^(BugSplatReportResult *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)0);
}

- (void)testPostException_UploadFailure_PropagatesTheUploadError
{
    [self installUploadService];
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:500]
                                      error:nil];

    XCTestExpectation *expectation = [self expectationWithDescription:@"post completes"];
    __block NSError *received = nil;

    [self.bugSplat postException:[NSException exceptionWithName:@"Boom" reason:nil userInfo:nil]
                      completion:^(BugSplatReportResult *result, NSError *error) {
        XCTAssertNil(result);
        received = error;
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertNotNil(received);
}

- (void)testPostException_NilCompletion_DoesNotCrash
{
    [self installUploadService];
    [self queueSuccessfulUploadFlow];

    XCTAssertNoThrow([self.bugSplat postException:[NSException exceptionWithName:@"Boom" reason:nil userInfo:nil]
                                       completion:nil]);
}

@end
