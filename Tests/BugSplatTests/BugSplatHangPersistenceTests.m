//
//  BugSplatHangPersistenceTests.m
//  BugSplatTests
//
//  Integration-style tests covering the hang delegate's disk persistence:
//  on hang, a .crash + .meta pair is written into the crashes directory;
//  on recovery, those files are removed. Uses a real PLCrashReporter to
//  generate the live report.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <TargetConditionals.h>
#import <XCTest/XCTest.h>

#import <BugSplat/BugSplat.h>
#import "BugSplat+Testing.h"
#import "BugSplatUploadService.h"
#import "MockURLSession.h"

// Keys shared with BugSplat.m. Duplicated here rather than exposed via a
// testing header because they are an implementation detail the backend also
// understands via well-known strings.
static NSString *const kAttributesKey = @"attributes";
static NSString *const kDatabaseKey = @"database";
static NSString *const kUserSubmittedKey = @"userSubmitted";
static NSString *const kTimestampKey = @"timestamp";
static NSString *const kHangAttrDurationMs = @"bugsplat-hang-duration-ms";
static NSString *const kHangAttrAppState = @"bugsplat-hang-app-state";
static NSString *const kHangAttrDetectedAt = @"bugsplat-hang-detected-at";
static NSString *const kHangAttrLaunchId = @"bugsplat-hang-launch-id";
static NSString *const kHangAttrFatal = @"bugsplat-hang-fatal";
static NSString *const kHangAttrRecoveredAfterMs = @"bugsplat-hang-recovered-after-ms";
static NSString *const kHangEnrichedKey = @"hangEnriched";
static NSString *const kHangReportOnNextLaunchKey = @"hangReportOnNextLaunch";
static NSString *const kFatalExceptionName = @"App Hang (Fatal)";
static NSString *const kNonFatalExceptionName = @"App Hang (Non-Fatal)";


@interface BugSplatHangPersistenceTests : XCTestCase
@property (nonatomic, strong) BugSplat *bugSplat;
@property (nonatomic, copy, nullable) NSString *filenameToCleanup;
@property (nonatomic, strong, nullable) MockURLSession *mockSession;
@end

@implementation BugSplatHangPersistenceTests

- (void)setUp
{
    [super setUp];
    // Use a regular BugSplat instance (not testInstance) so it carries a real
    // PLCrashReporter - needed for the live-report capture path.
    self.bugSplat = [[BugSplat alloc] init];
    self.bugSplat.bugSplatDatabase = @"hangtestdb";
    self.bugSplat.applicationName = @"HangTest";
    self.bugSplat.applicationVersion = @"1.0";
    self.bugSplat.enableHangDetection = YES;
    [self.bugSplat setupHangInfrastructureForTesting];
}

- (void)tearDown
{
    NSString *filename = self.filenameToCleanup;
    if (filename) {
        [self removeReportFilesForFilename:filename];
    }
    self.filenameToCleanup = nil;
    [self.mockSession reset];
    self.mockSession = nil;
    self.bugSplat = nil;
    [super tearDown];
}

#pragma mark - Helpers

- (void)removeReportFilesForFilename:(NSString *)filename
{
    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *ext in @[@"crash", @"meta"]) {
        NSString *path = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:ext];
        if ([fm fileExistsAtPath:path]) {
            [fm removeItemAtPath:path error:nil];
        }
    }
}

- (void)drainHangQueue
{
    dispatch_queue_t queue = [self.bugSplat hangQueueForTesting];
    XCTAssertNotNil(queue);
    dispatch_sync(queue, ^{});
}

/// The non-fatal path hops to the main queue (to ask the delegate for attachments, as the
/// crash path does) and back to the hang queue, so draining the hang queue alone is not
/// enough - the main run loop has to turn. Spins it until `condition` holds or time runs out.
- (BOOL)waitForCondition:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return condition();
}

- (NSString *)crashPathForFilename:(NSString *)filename
{
    return [[[self.bugSplat crashesDirectoryPath] stringByAppendingPathComponent:filename]
            stringByAppendingPathExtension:@"crash"];
}

- (NSString *)metaPathForFilename:(NSString *)filename
{
    return [[[self.bugSplat crashesDirectoryPath] stringByAppendingPathComponent:filename]
            stringByAppendingPathExtension:@"meta"];
}

- (NSDictionary *)metadataForFilename:(NSString *)filename
{
    return [NSDictionary dictionaryWithContentsOfFile:[self metaPathForFilename:filename]];
}

- (NSString *)reportTextForFilename:(NSString *)filename
{
    return [NSString stringWithContentsOfFile:[self crashPathForFilename:filename]
                                     encoding:NSUTF8StringEncoding
                                        error:nil];
}

/// Install an upload service backed by a mock session. When `succeeds` is YES the three
/// steps of the presigned-URL flow are queued; otherwise the first step fails.
- (void)installMockUploadServiceSucceeding:(BOOL)succeeds
{
    self.mockSession = [[MockURLSession alloc] init];

    if (succeeds) {
        NSDictionary *presigned = @{@"url": @"https://s3.amazonaws.com/bucket/key?signature=abc"};
        [self.mockSession queueResponseWithData:[NSJSONSerialization dataWithJSONObject:presigned options:0 error:nil]
                                       response:[MockURLSession jsonResponseWithStatusCode:200]
                                          error:nil];
        [self.mockSession queueResponseWithData:nil
                                       response:[MockURLSession responseWithStatusCode:200]
                                          error:nil];
        NSDictionary *commit = @{@"status": @"success", @"infoUrl": @"https://app.bugsplat.com/crash/1"};
        [self.mockSession queueResponseWithData:[NSJSONSerialization dataWithJSONObject:commit options:0 error:nil]
                                       response:[MockURLSession jsonResponseWithStatusCode:200]
                                          error:nil];
    } else {
        [self.mockSession queueResponseWithData:nil
                                       response:nil
                                          error:[NSError errorWithDomain:NSURLErrorDomain
                                                                    code:NSURLErrorNotConnectedToInternet
                                                                userInfo:nil]];
    }

    BugSplatUploadService *service = [[BugSplatUploadService alloc] initWithDatabase:@"hangtestdb"
                                                                    applicationName:@"HangTest"
                                                                 applicationVersion:@"1.0"
                                                                         urlSession:self.mockSession];
    [self.bugSplat setUploadServiceForTesting:service];
}

/// Detect a hang and wait for the report to land on disk, returning its basename.
- (NSString *)persistHangReport
{
    [self.bugSplat hangTracker:nil didDetectHangWithDuration:3.0 appState:@"active"];
    [self drainHangQueue];
    NSString *filename = [self.bugSplat currentHangFilename];
    XCTAssertNotNil(filename, @"Hang delegate should have persisted a report");
    self.filenameToCleanup = filename;
    return filename;
}

#pragma mark - Tests

- (void)testHangDelegate_WritesCrashAndMetaFiles
{
    [self.bugSplat hangTracker:nil didDetectHangWithDuration:3.5 appState:@"active"];
    [self drainHangQueue];

    NSString *filename = [self.bugSplat currentHangFilename];
    XCTAssertNotNil(filename, @"Hang delegate should have persisted a report");
    XCTAssertTrue([filename hasSuffix:@"-hang"], @"Hang report filename should carry the -hang suffix");
    self.filenameToCleanup = filename;

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *crashPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"crash"];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];

    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([fm fileExistsAtPath:crashPath]);
    XCTAssertTrue([fm fileExistsAtPath:metaPath]);
}

- (void)testHangDelegate_ReportTextContainsExceptionName
{
    [self.bugSplat hangTracker:nil didDetectHangWithDuration:3.5 appState:@"active"];
    [self drainHangQueue];

    NSString *filename = [self.bugSplat currentHangFilename];
    XCTAssertNotNil(filename);
    self.filenameToCleanup = filename;

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *crashPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"crash"];
    NSString *crashText = [NSString stringWithContentsOfFile:crashPath encoding:NSUTF8StringEncoding error:nil];
    XCTAssertNotNil(crashText);

    XCTAssertTrue([crashText containsString:@"App Hang (Fatal)"],
                  @"Report text should carry the App Hang (Fatal) exception name; got:\n%@", crashText);
    XCTAssertTrue([crashText containsString:@"Main thread unresponsive for 3500 ms"],
                  @"Report text should carry the exception reason with duration; got:\n%@", crashText);
}

- (void)testHangDelegate_MetadataHasDatabaseAndUserSubmittedFlag
{
    [self.bugSplat hangTracker:nil didDetectHangWithDuration:2.0 appState:@"active"];
    [self drainHangQueue];

    NSString *filename = [self.bugSplat currentHangFilename];
    XCTAssertNotNil(filename);
    self.filenameToCleanup = filename;

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
    XCTAssertNotNil(meta);

    XCTAssertEqualObjects(meta[kDatabaseKey], @"hangtestdb");
    XCTAssertEqualObjects(meta[kUserSubmittedKey], @YES);
    XCTAssertNotNil(meta[kTimestampKey]);
}

- (void)testHangDelegate_MetadataContainsCurrentSessionID
{
    [self.bugSplat hangTracker:nil didDetectHangWithDuration:2.0 appState:@"active"];
    [self drainHangQueue];

    NSString *filename = [self.bugSplat currentHangFilename];
    XCTAssertNotNil(filename);
    self.filenameToCleanup = filename;

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
    XCTAssertNotNil(meta);

    // The hang happened in THIS session, so the persisted ID must be the current one.
    XCTAssertEqualObjects(meta[@"sessionID"], self.bugSplat.sessionID.UUIDString);
}

- (void)testHangDelegate_MetadataContainsHangAttributes
{
    [self.bugSplat hangTracker:nil didDetectHangWithDuration:2.5 appState:@"background"];
    [self drainHangQueue];

    NSString *filename = [self.bugSplat currentHangFilename];
    XCTAssertNotNil(filename);
    self.filenameToCleanup = filename;

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
    NSDictionary *attributes = meta[kAttributesKey];
    XCTAssertNotNil(attributes);

    XCTAssertEqualObjects(attributes[kHangAttrDurationMs], @"2500");
    XCTAssertEqualObjects(attributes[kHangAttrAppState], @"background");
    XCTAssertNotNil(attributes[kHangAttrDetectedAt]);
    XCTAssertNotNil(attributes[kHangAttrLaunchId]);
}

- (void)testHangDelegate_RecoveryRemovesPersistedFiles
{
    [self.bugSplat hangTracker:nil didDetectHangWithDuration:3.0 appState:@"active"];
    [self drainHangQueue];

    NSString *filename = [self.bugSplat currentHangFilename];
    XCTAssertNotNil(filename);

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *crashPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"crash"];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([fm fileExistsAtPath:crashPath]);

    // Main thread "recovers" - persisted files should be deleted.
    [self.bugSplat hangTrackerDidRecoverFromHang:nil];
    [self drainHangQueue];

    XCTAssertFalse([fm fileExistsAtPath:crashPath], @"Crash file should be deleted on recovery");
    XCTAssertFalse([fm fileExistsAtPath:metaPath], @"Meta file should be deleted on recovery");
    XCTAssertNil([self.bugSplat currentHangFilename]);
}

#pragma mark - Non-Fatal Hang Reporting

- (void)testNonFatalHangReporting_DefaultsToDisabled
{
    BugSplat *fresh = [[BugSplat alloc] init];
    XCTAssertFalse(fresh.enableNonFatalHangReporting,
                   @"Non-fatal hang reporting must be opt-in");
}

- (void)testFatalHangReport_DoesNotCarryNonFatalAttributes
{
    // enableHangDetection alone must produce exactly the report it produced before.
    NSString *filename = [self persistHangReport];

    NSString *text = [self reportTextForFilename:filename];
    XCTAssertTrue([text containsString:kFatalExceptionName]);
    XCTAssertFalse([text containsString:kNonFatalExceptionName]);

    NSDictionary *attributes = [self metadataForFilename:filename][kAttributesKey];
    XCTAssertNil(attributes[kHangAttrFatal]);
    XCTAssertNil(attributes[kHangAttrRecoveredAfterMs]);
}

- (void)testPersistedMetadata_MarksReportUploadableWhenFatalDetectionEnabled
{
    NSString *filename = [self persistHangReport];
    XCTAssertEqualObjects([self metadataForFilename:filename][kHangReportOnNextLaunchKey], @YES);
}

- (void)testPersistedMetadata_MarksReportNotUploadableWhenOnlyNonFatalEnabled
{
    self.bugSplat.enableHangDetection = NO;
    self.bugSplat.enableNonFatalHangReporting = YES;

    NSString *filename = [self persistHangReport];
    XCTAssertEqualObjects([self metadataForFilename:filename][kHangReportOnNextLaunchKey], @NO,
                          @"A hang captured without the fatal opt-in must not be uploaded at the next launch");
}

- (void)testRecovery_WithNonFatalReportingDisabled_DiscardsWithoutUploading
{
    [self installMockUploadServiceSucceeding:YES];

    NSString *filename = [self persistHangReport];
    [self.bugSplat hangTrackerDidRecoverFromHang:nil];
    [self drainHangQueue];

    // Give any (unwanted) asynchronous upload a chance to start before asserting.
    [self waitForCondition:^BOOL { return self.mockSession.requestCount > 0; } timeout:0.5];

    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertFalse([fm fileExistsAtPath:[self crashPathForFilename:filename]]);
    XCTAssertFalse([fm fileExistsAtPath:[self metaPathForFilename:filename]]);
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)0,
                   @"Recovered hangs must not be uploaded unless the new opt-in is set");
    XCTAssertEqual([self.bugSplat nonFatalHangReportCountForTesting], (NSUInteger)0);
}

- (void)testRecovery_WithNonFatalReportingEnabled_RewritesReportAsNonFatal
{
    self.bugSplat.enableNonFatalHangReporting = YES;
    // No upload service: the rewritten report stays on disk so it can be inspected, which
    // is also the behavior an offline app gets (the next launch retries the upload).

    [self.bugSplat hangTracker:nil didDetectHangWithDuration:2.5 appState:@"background"];
    [self drainHangQueue];
    NSString *filename = [self.bugSplat currentHangFilename];
    XCTAssertNotNil(filename);
    self.filenameToCleanup = filename;

    [self.bugSplat hangTrackerDidRecoverFromHang:nil];
    [self drainHangQueue];
    XCTAssertTrue([self waitForCondition:^BOOL {
        return [[self metadataForFilename:filename][kHangEnrichedKey] boolValue];
    } timeout:5.0], @"Recovered hang report should have been processed");

    NSString *text = [self reportTextForFilename:filename];
    XCTAssertTrue([text containsString:kNonFatalExceptionName],
                  @"Recovered hang should be renamed to the non-fatal exception; got:\n%@", text);
    XCTAssertFalse([text containsString:kFatalExceptionName],
                   @"No trace of the fatal exception name may remain, or the two would group together");
    XCTAssertTrue([text containsString:@"Main thread unresponsive for 2500 ms"],
                  @"The reason string is deliberately left untouched");

    NSDictionary *metadata = [self metadataForFilename:filename];
    NSDictionary *attributes = metadata[kAttributesKey];
    XCTAssertEqualObjects(attributes[kHangAttrFatal], @"false");
    XCTAssertNotNil(attributes[kHangAttrRecoveredAfterMs]);
    // The fatal report's attribute shape is preserved.
    XCTAssertEqualObjects(attributes[kHangAttrDurationMs], @"2500");
    XCTAssertEqualObjects(attributes[kHangAttrAppState], @"background");
    XCTAssertNotNil(attributes[kHangAttrDetectedAt]);
    XCTAssertNotNil(attributes[kHangAttrLaunchId]);
    // Uploadable from here on, even though fatal detection captured it.
    XCTAssertEqualObjects(metadata[kHangReportOnNextLaunchKey], @YES);
    XCTAssertEqualObjects(metadata[kUserSubmittedKey], @YES);

    XCTAssertEqual([self.bugSplat nonFatalHangReportCountForTesting], (NSUInteger)1);
}

- (void)testRecovery_WithNonFatalReportingEnabled_UploadsAndRemovesFiles
{
    self.bugSplat.enableNonFatalHangReporting = YES;
    [self installMockUploadServiceSucceeding:YES];

    NSString *filename = [self persistHangReport];
    [self.bugSplat hangTrackerDidRecoverFromHang:nil];
    [self drainHangQueue];

    // Cleanup removes the .crash before the .meta, so wait on both rather than racing
    // the gap between the two deletions.
    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([self waitForCondition:^BOOL {
        return ![fm fileExistsAtPath:[self crashPathForFilename:filename]]
            && ![fm fileExistsAtPath:[self metaPathForFilename:filename]];
    } timeout:10.0], @"Report should be removed after a successful upload");
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)3,
                   @"Non-fatal hangs use the same 3-step upload flow as crashes");
    XCTAssertEqual([self.bugSplat nonFatalHangReportCountForTesting], (NSUInteger)1);
    // The app is still running and no crash-pipeline state was disturbed.
    XCTAssertFalse([self.bugSplat isSendingInProgress]);
}

- (void)testRecovery_NonFatalUploadFailure_LeavesReportForNextLaunch
{
    self.bugSplat.enableNonFatalHangReporting = YES;
    [self installMockUploadServiceSucceeding:NO];

    NSString *filename = [self persistHangReport];
    [self.bugSplat hangTrackerDidRecoverFromHang:nil];
    [self drainHangQueue];

    XCTAssertTrue([self waitForCondition:^BOOL {
        return self.mockSession.requestCount > 0;
    } timeout:10.0], @"Upload should have been attempted");

    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([fm fileExistsAtPath:[self crashPathForFilename:filename]],
                  @"A failed upload must leave the report on disk for the next launch");
    NSDictionary *metadata = [self metadataForFilename:filename];
    XCTAssertEqualObjects(metadata[kHangReportOnNextLaunchKey], @YES);
    XCTAssertEqualObjects(metadata[kUserSubmittedKey], @YES,
                          @"The retry must be silent - no dialog for a hang the app recovered from");
}

- (void)testNonFatalHangReporting_SessionCapSuppressesFurtherReports
{
    self.bugSplat.enableNonFatalHangReporting = YES;
    [self installMockUploadServiceSucceeding:YES];

    NSUInteger cap = [BugSplat maxNonFatalHangReportsPerSessionForTesting];
    XCTAssertGreaterThan(cap, (NSUInteger)0);
    [self.bugSplat setNonFatalHangReportCountForTesting:cap];

    NSString *filename = [self persistHangReport];
    [self.bugSplat hangTrackerDidRecoverFromHang:nil];
    [self drainHangQueue];
    [self waitForCondition:^BOOL { return self.mockSession.requestCount > 0; } timeout:0.5];

    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertFalse([fm fileExistsAtPath:[self crashPathForFilename:filename]],
                   @"A suppressed report is discarded, not left to accumulate on disk");
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)0);
    XCTAssertEqual([self.bugSplat nonFatalHangReportCountForTesting], cap);
}

- (void)testNonFatalHangReporting_MinimumIntervalSuppressesRapidReports
{
    self.bugSplat.enableNonFatalHangReporting = YES;
    [self installMockUploadServiceSucceeding:YES];

    XCTAssertGreaterThan([BugSplat minNonFatalHangReportIntervalForTesting], 0.0);
    [self.bugSplat setNonFatalHangReportCountForTesting:0];
    [self.bugSplat setLastNonFatalHangReportTimeForTesting:CFAbsoluteTimeGetCurrent()];

    NSString *filename = [self persistHangReport];
    [self.bugSplat hangTrackerDidRecoverFromHang:nil];
    [self drainHangQueue];
    [self waitForCondition:^BOOL { return self.mockSession.requestCount > 0; } timeout:0.5];

    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertFalse([fm fileExistsAtPath:[self crashPathForFilename:filename]]);
    XCTAssertEqual(self.mockSession.requestCount, (NSUInteger)0,
                   @"Back-to-back hangs must not each produce an upload");
    XCTAssertEqual([self.bugSplat nonFatalHangReportCountForTesting], (NSUInteger)0);
}

#pragma mark - Next-Launch Handling

- (void)testNextLaunch_KeepsSurvivingHangReportWhenFatalDetectionWasEnabled
{
    NSString *filename = [self persistHangReport];

    // Simulate the next launch seeing the report the app never recovered from.
    [self.bugSplat enrichHangReportWithFilename:filename];

    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([fm fileExistsAtPath:[self crashPathForFilename:filename]]);
    XCTAssertEqualObjects([self metadataForFilename:filename][kHangEnrichedKey], @YES);
}

- (void)testNextLaunch_DiscardsSurvivingHangReportWhenOnlyNonFatalWasEnabled
{
    self.bugSplat.enableHangDetection = NO;
    self.bugSplat.enableNonFatalHangReporting = YES;

    NSString *filename = [self persistHangReport];

    // The report survived to a new launch, so the hang was fatal - and the integrator
    // never opted in to fatal hang reports.
    [self.bugSplat enrichHangReportWithFilename:filename];

    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertFalse([fm fileExistsAtPath:[self crashPathForFilename:filename]],
                   @"A fatal hang must not be uploaded when only non-fatal reporting was enabled");
    XCTAssertFalse([fm fileExistsAtPath:[self metaPathForFilename:filename]]);
}

#pragma mark - Tracker Start Gating

- (void)testStartHangDetection_DoesNotStartWhenBothOptInsAreOff
{
    BugSplat *bugSplat = [[BugSplat alloc] init];
    bugSplat.bugSplatDatabase = @"hangtestdb";
    bugSplat.hangDetectionThreshold = 60.0;

    [bugSplat startHangDetectionIfEnabled];

    XCTAssertNil([bugSplat hangTrackerForTesting]);
}

- (void)testStartHangDetection_StartsForNonFatalOptInAlone
{
    BugSplat *bugSplat = [[BugSplat alloc] init];
    bugSplat.bugSplatDatabase = @"hangtestdb";
    // High threshold so the tracker cannot fire while the test runs.
    bugSplat.hangDetectionThreshold = 60.0;
    bugSplat.enableNonFatalHangReporting = YES;

    [bugSplat startHangDetectionIfEnabled];

    BugSplatHangTracker *tracker = [bugSplat hangTrackerForTesting];
    XCTAssertNotNil(tracker, @"Non-fatal reporting alone should start main-thread monitoring");
    XCTAssertTrue(tracker.isRunning);
    [tracker stop];
}

- (void)testHangDelegate_FallsThroughWithoutAppState
{
    // Pass a nil-safe "unknown" value - delegate should accept it and persist fine.
    [self.bugSplat hangTracker:nil didDetectHangWithDuration:2.0 appState:@"unknown"];
    [self drainHangQueue];

    NSString *filename = [self.bugSplat currentHangFilename];
    XCTAssertNotNil(filename);
    self.filenameToCleanup = filename;

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
    NSDictionary *attributes = meta[kAttributesKey];
    XCTAssertEqualObjects(attributes[kHangAttrAppState], @"unknown");
}

@end
