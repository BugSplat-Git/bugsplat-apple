//
//  BugSplatSessionIDTests.m
//  BugSplatTests
//
//  Tests for session ID generation, crash-time embedding via PLCrashReporter
//  customData, recovery at next launch, and delivery through the sessionID-aware
//  BugSplatDelegate callbacks (issue #65).
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
#import "MockCrashReporter.h"
#import "MockCrashStorage.h"
#import "MockUserDefaults.h"
#import "MockBundle.h"
#import "MockURLSession.h"

// Mirrors kBugSplatMetaKeySessionID in BugSplat.m - a well-known persisted string.
static NSString *const kSessionIDKey = @"sessionID";

// Live-report generation is part of PLCrashReporter but not of the injection
// protocol; declare just the selector we need so tests can drive a real reporter
// without importing the vendored framework headers.
@protocol BugSplatLiveReportGenerating <NSObject>
- (NSData *)generateLiveReportWithException:(NSException *)exception error:(NSError **)error;
@end

#pragma mark - Recording delegates

/// Implements ONLY the sessionID-aware delegate methods and records what it receives.
@interface SessionIDRecordingDelegate : NSObject <BugSplatDelegate>
@property (nonatomic, assign) BOOL attachmentsCallbackInvoked;   // plural variant
@property (nonatomic, assign) BOOL attachmentCallbackInvoked;    // singular variant
@property (nonatomic, assign) BOOL applicationLogCallbackInvoked;
@property (nonatomic, assign) BOOL willSendCallbackInvoked;
@property (nonatomic, assign) BOOL didFinishCallbackInvoked;
@property (nonatomic, assign) BOOL didFailCallbackInvoked;
@property (nonatomic, strong, nullable) NSUUID *receivedAttachmentSessionID;
@property (nonatomic, strong, nullable) NSUUID *receivedApplicationLogSessionID;
@property (nonatomic, strong, nullable) NSUUID *receivedWillSendSessionID;
@property (nonatomic, strong, nullable) NSUUID *receivedDidFinishSessionID;
@property (nonatomic, strong, nullable) NSUUID *receivedDidFailSessionID;
@end

@implementation SessionIDRecordingDelegate

- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    self.attachmentsCallbackInvoked = YES;
    self.receivedAttachmentSessionID = sessionID;
    return @[];
}

- (BugSplatAttachment *)attachmentForBugSplat:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    self.attachmentCallbackInvoked = YES;
    self.receivedAttachmentSessionID = sessionID;
    return nil;
}

- (NSString *)applicationLogForBugSplat:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    self.applicationLogCallbackInvoked = YES;
    self.receivedApplicationLogSessionID = sessionID;
    return @"session log";
}

- (void)bugSplatWillSendCrashReport:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    self.willSendCallbackInvoked = YES;
    self.receivedWillSendSessionID = sessionID;
}

- (void)bugSplatDidFinishSendingCrashReport:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    self.didFinishCallbackInvoked = YES;
    self.receivedDidFinishSessionID = sessionID;
}

- (void)bugSplat:(BugSplat *)bugSplat didFailWithError:(NSError *)error sessionID:(NSUUID *)sessionID
{
    self.didFailCallbackInvoked = YES;
    self.receivedDidFailSessionID = sessionID;
}

@end

/// Implements ONLY the legacy (sessionID-less) delegate methods.
@interface LegacyRecordingDelegate : NSObject <BugSplatDelegate>
@property (nonatomic, assign) BOOL legacyAttachmentsCallbackInvoked;
@property (nonatomic, assign) BOOL legacyAttachmentCallbackInvoked;
@end

@implementation LegacyRecordingDelegate

- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat
{
    self.legacyAttachmentsCallbackInvoked = YES;
    return @[];
}

- (BugSplatAttachment *)attachmentForBugSplat:(BugSplat *)bugSplat
{
    self.legacyAttachmentCallbackInvoked = YES;
    return nil;
}

@end

/// Implements BOTH generations so preference can be asserted.
@interface BothGenerationsDelegate : SessionIDRecordingDelegate
@property (nonatomic, assign) BOOL legacyAttachmentsCallbackInvoked;
@property (nonatomic, assign) BOOL legacyAttachmentCallbackInvoked;
@end

@implementation BothGenerationsDelegate

- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat
{
    self.legacyAttachmentsCallbackInvoked = YES;
    return @[];
}

- (BugSplatAttachment *)attachmentForBugSplat:(BugSplat *)bugSplat
{
    self.legacyAttachmentCallbackInvoked = YES;
    return nil;
}

@end

/// Returns a real attachment + application log so hang enrichment can be verified end
/// to end, recording the sessionID it was handed and how many times it was asked.
@interface HangEnrichmentDelegate : NSObject <BugSplatDelegate>
@property (nonatomic, assign) NSInteger attachmentCallCount;
@property (nonatomic, assign) NSInteger applicationLogCallCount;
@property (nonatomic, strong, nullable) NSUUID *receivedAttachmentSessionID;
@property (nonatomic, strong, nullable) NSUUID *receivedApplicationLogSessionID;
@end

@implementation HangEnrichmentDelegate

- (BugSplatAttachment *)makeAttachment
{
    NSData *data = [@"hang session log contents" dataUsingEncoding:NSUTF8StringEncoding];
    return [[BugSplatAttachment alloc] initWithFilename:@"session.log"
                                         attachmentData:data
                                            contentType:@"text/plain"];
}

- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    self.attachmentCallCount++;
    self.receivedAttachmentSessionID = sessionID;
    return @[[self makeAttachment]];
}

- (BugSplatAttachment *)attachmentForBugSplat:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    self.attachmentCallCount++;
    self.receivedAttachmentSessionID = sessionID;
    return [self makeAttachment];
}

- (NSString *)applicationLogForBugSplat:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    self.applicationLogCallCount++;
    self.receivedApplicationLogSessionID = sessionID;
    return @"hang app log";
}

@end

/// Returns TWO attachments from the plural delegate so multi-attachment support can be
/// verified on every platform (issue #69).
@interface MultiAttachmentDelegate : NSObject <BugSplatDelegate>
@end

@implementation MultiAttachmentDelegate

- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    BugSplatAttachment *playerLog =
        [[BugSplatAttachment alloc] initWithFilename:@"Player.log"
                                      attachmentData:[@"player log" dataUsingEncoding:NSUTF8StringEncoding]
                                         contentType:@"text/plain"];
    BugSplatAttachment *sessionLog =
        [[BugSplatAttachment alloc] initWithFilename:@"session.log"
                                      attachmentData:[@"session log" dataUsingEncoding:NSUTF8StringEncoding]
                                         contentType:@"text/plain"];
    return @[playerLog, sessionLog];
}

@end

#pragma mark - Tests

@interface BugSplatSessionIDTests : XCTestCase

@property (nonatomic, strong) BugSplat *bugSplat;
@property (nonatomic, strong) MockCrashReporter *mockCrashReporter;
@property (nonatomic, strong) MockCrashStorage *mockCrashStorage;
@property (nonatomic, strong) MockUserDefaults *mockUserDefaults;
@property (nonatomic, strong) MockBundle *mockBundle;
@property (nonatomic, strong) NSMutableArray<NSString *> *filenamesToCleanup;

@end

@implementation BugSplatSessionIDTests

- (void)setUp
{
    [super setUp];

    self.mockCrashReporter = [[MockCrashReporter alloc] init];
    self.mockCrashStorage = [[MockCrashStorage alloc] init];
    self.mockUserDefaults = [[MockUserDefaults alloc] init];
    self.mockBundle = [[MockBundle alloc] init];
    self.filenamesToCleanup = [NSMutableArray array];

    [self.mockBundle setObject:@"TestApp" forInfoDictionaryKey:@"CFBundleName"];
    [self.mockBundle setObject:@"1.0.0" forInfoDictionaryKey:@"CFBundleShortVersionString"];
    [self.mockBundle setObject:@"testdb" forInfoDictionaryKey:@"BugSplatDatabase"];

    self.bugSplat = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                               crashStorage:self.mockCrashStorage
                                               userDefaults:self.mockUserDefaults
                                                     bundle:self.mockBundle];
}

- (void)tearDown
{
    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *filename in self.filenamesToCleanup) {
        for (NSString *ext in @[@"crash", @"meta"]) {
            NSString *path = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:ext];
            [fm removeItemAtPath:path error:nil];
        }
        // Attachments are persisted as {filename}-{index}.data
        for (NSInteger index = 0; index < 5; index++) {
            NSString *attachmentName = [NSString stringWithFormat:@"%@-%ld", filename, (long)index];
            NSString *path = [[dir stringByAppendingPathComponent:attachmentName] stringByAppendingPathExtension:@"data"];
            [fm removeItemAtPath:path error:nil];
        }
    }

    [self.mockCrashReporter reset];
    [self.mockCrashStorage reset];
    [self.mockUserDefaults reset];
    self.bugSplat = nil;

    [super tearDown];
}

#pragma mark - Helpers

/// Generates real PLCrashReporter report data whose embedded customData carries
/// the given session ID, simulating a crash captured during a previous session.
- (NSData *)crashReportDataWithEmbeddedSessionID:(NSUUID *)sessionID
{
    // A real (non-test) instance carries a real PLCrashReporter.
    BugSplat *previousSession = [[BugSplat alloc] init];
    id<BugSplatCrashReporterProtocol> reporter = [previousSession crashReporter];

    NSDictionary *crashMetadata = @{
        @"database": @"testdb",
        @"applicationName": @"TestApp",
        @"applicationVersion": @"1.0.0",
        kSessionIDKey: sessionID.UUIDString,
    };
    NSError *archiveError = nil;
    NSData *customData = [NSKeyedArchiver archivedDataWithRootObject:crashMetadata
                                               requiringSecureCoding:NO
                                                               error:&archiveError];
    XCTAssertNotNil(customData);
    reporter.customData = customData;

    NSException *exception = [NSException exceptionWithName:@"TestCrash" reason:@"simulated" userInfo:nil];
    NSError *reportError = nil;
    NSData *reportData = [(id<BugSplatLiveReportGenerating>)reporter generateLiveReportWithException:exception
                                                                                               error:&reportError];
    XCTAssertNotNil(reportData, @"Failed to generate live crash report: %@", reportError);
    return reportData;
}

- (void)recordCurrentCrashFilenameForCleanup
{
    NSString *filename = [self.bugSplat currentCrashFilename];
    if (filename) {
        [self.filenamesToCleanup addObject:filename];
    }
}

#pragma mark - Property tests

- (void)testSessionID_IsGeneratedAndStable
{
    NSUUID *first = self.bugSplat.sessionID;
    XCTAssertNotNil(first);
    XCTAssertEqualObjects(first, self.bugSplat.sessionID, @"sessionID should be stable for the lifetime of the instance");
}

- (void)testSessionID_DiffersBetweenInstances
{
    BugSplat *other = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                 crashStorage:self.mockCrashStorage
                                                 userDefaults:self.mockUserDefaults
                                                       bundle:self.mockBundle];
    XCTAssertNotEqualObjects(self.bugSplat.sessionID, other.sessionID);
}

- (void)testStart_EmbedsSessionIDInCrashReporterCustomData
{
    [self.bugSplat setDebuggerAttachedOverride:@NO];
    [self.bugSplat start];

    XCTAssertNotNil(self.mockCrashReporter.customData, @"start should set customData on the crash reporter");

    NSError *error = nil;
    NSSet *classes = [NSSet setWithObjects:[NSDictionary class], [NSString class], nil];
    NSDictionary *decoded = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes
                                                                 fromData:self.mockCrashReporter.customData
                                                                    error:&error];
    XCTAssertNotNil(decoded, @"customData should decode: %@", error);
    XCTAssertEqualObjects(decoded[kSessionIDKey], self.bugSplat.sessionID.UUIDString,
                          @"customData should carry the current session's ID");
}

#pragma mark - Crash processing tests

- (void)testHandleNewCrash_PassesCrashedSessionIDToDelegate
{
    NSUUID *crashedSessionID = [NSUUID UUID];
    self.mockCrashReporter.hasPendingReport = YES;
    self.mockCrashReporter.pendingCrashReportData = [self crashReportDataWithEmbeddedSessionID:crashedSessionID];

    SessionIDRecordingDelegate *delegate = [[SessionIDRecordingDelegate alloc] init];
    self.bugSplat.delegate = delegate;

    [self.bugSplat handleNewCrashFromPLCrashReporter];
    [self recordCurrentCrashFilenameForCleanup];

    XCTAssertTrue(delegate.attachmentsCallbackInvoked, @"plural sessionID-aware variant should be preferred on every platform");
    XCTAssertFalse(delegate.attachmentCallbackInvoked);
    XCTAssertEqualObjects(delegate.receivedAttachmentSessionID, crashedSessionID,
                          @"Delegate should receive the CRASHED session's ID");
    XCTAssertNotEqualObjects(delegate.receivedAttachmentSessionID, self.bugSplat.sessionID,
                             @"The crashed session's ID is not the current session's ID");

    XCTAssertTrue(delegate.applicationLogCallbackInvoked);
    XCTAssertEqualObjects(delegate.receivedApplicationLogSessionID, crashedSessionID);
}

- (void)testHandleNewCrash_PersistsCrashedSessionIDInMetadata
{
    NSUUID *crashedSessionID = [NSUUID UUID];
    self.mockCrashReporter.hasPendingReport = YES;
    self.mockCrashReporter.pendingCrashReportData = [self crashReportDataWithEmbeddedSessionID:crashedSessionID];

    [self.bugSplat handleNewCrashFromPLCrashReporter];
    [self recordCurrentCrashFilenameForCleanup];

    NSString *filename = [self.bugSplat currentCrashFilename];
    XCTAssertNotNil(filename);

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
    XCTAssertNotNil(meta);
    XCTAssertEqualObjects(meta[kSessionIDKey], crashedSessionID.UUIDString,
                          @"The crashed session's ID should survive in the .meta file for offline retries");
}

- (void)testHandleNewCrash_PrefersSessionIDVariantOverLegacy
{
    NSUUID *crashedSessionID = [NSUUID UUID];
    self.mockCrashReporter.hasPendingReport = YES;
    self.mockCrashReporter.pendingCrashReportData = [self crashReportDataWithEmbeddedSessionID:crashedSessionID];

    BothGenerationsDelegate *delegate = [[BothGenerationsDelegate alloc] init];
    self.bugSplat.delegate = delegate;

    [self.bugSplat handleNewCrashFromPLCrashReporter];
    [self recordCurrentCrashFilenameForCleanup];

    XCTAssertTrue(delegate.attachmentsCallbackInvoked);
    XCTAssertFalse(delegate.legacyAttachmentsCallbackInvoked, @"Legacy variant should not be called when the sessionID-aware variant is implemented");
    XCTAssertFalse(delegate.legacyAttachmentCallbackInvoked, @"Legacy variant should not be called when the sessionID-aware variant is implemented");
}

- (void)testHandleNewCrash_FallsBackToLegacyDelegate
{
    self.mockCrashReporter.hasPendingReport = YES;
    self.mockCrashReporter.pendingCrashReportData = [self crashReportDataWithEmbeddedSessionID:[NSUUID UUID]];

    LegacyRecordingDelegate *delegate = [[LegacyRecordingDelegate alloc] init];
    self.bugSplat.delegate = delegate;

    [self.bugSplat handleNewCrashFromPLCrashReporter];
    [self recordCurrentCrashFilenameForCleanup];

    XCTAssertTrue(delegate.legacyAttachmentsCallbackInvoked, @"Legacy delegates must keep working");
}

- (void)testHandleNewCrash_PersistsEveryAttachmentFromPluralDelegate
{
    // Attributes are sent as form fields on the upload request, so an app is free to
    // spend all of its attachments on its own files - on iOS as well as macOS.
    self.mockCrashReporter.hasPendingReport = YES;
    self.mockCrashReporter.pendingCrashReportData = [self crashReportDataWithEmbeddedSessionID:[NSUUID UUID]];

    MultiAttachmentDelegate *delegate = [[MultiAttachmentDelegate alloc] init];
    self.bugSplat.delegate = delegate;

    XCTAssertTrue([self.bugSplat setValue:@"boss-fight" forAttribute:@"level"]);

    [self.bugSplat handleNewCrashFromPLCrashReporter];
    [self recordCurrentCrashFilenameForCleanup];

    NSString *filename = [self.bugSplat currentCrashFilename];
    XCTAssertNotNil(filename);

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSArray<NSString *> *expectedFilenames = @[@"Player.log", @"session.log"];
    for (NSUInteger index = 0; index < expectedFilenames.count; index++) {
        NSString *path = [[dir stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"%@-%lu", filename, (unsigned long)index]]
                          stringByAppendingPathExtension:@"data"];
        NSData *archived = [NSData dataWithContentsOfFile:path];
        XCTAssertNotNil(archived, @"Attachment %lu should have been persisted", (unsigned long)index);

        NSError *error = nil;
        BugSplatAttachment *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[BugSplatAttachment class]
                                                                       fromData:archived
                                                                          error:&error];
        XCTAssertNil(error);
        XCTAssertEqualObjects(decoded.filename, expectedFilenames[index]);
    }
}

- (void)testHandleNewCrash_NilSessionIDWhenReportPredatesSessionTracking
{
    // Unparseable crash data simulates a report with no recoverable customData
    // (e.g. recorded by an SDK version that predates session tracking).
    self.mockCrashReporter.hasPendingReport = YES;
    self.mockCrashReporter.pendingCrashReportData = [@"fake crash" dataUsingEncoding:NSUTF8StringEncoding];

    SessionIDRecordingDelegate *delegate = [[SessionIDRecordingDelegate alloc] init];
    self.bugSplat.delegate = delegate;

    [self.bugSplat handleNewCrashFromPLCrashReporter];
    [self recordCurrentCrashFilenameForCleanup];

    XCTAssertTrue(delegate.attachmentsCallbackInvoked);
    XCTAssertNil(delegate.receivedAttachmentSessionID,
                 @"sessionID should be nil for reports without embedded session data");
}

#pragma mark - Upload callback tests

- (void)testSubmit_DeliversPersistedSessionIDToWillSendAndDidFail
{
    // Plant a crash + meta pair as if persisted at a previous launch. The name sorts
    // after any timestamp-based leftovers so processPendingCrashReports picks it.
    NSUUID *crashedSessionID = [NSUUID UUID];
    NSString *filename = @"99999999999";
    [self.filenamesToCleanup addObject:filename];

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *crashPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"crash"];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    XCTAssertTrue([[@"test crash report" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:crashPath atomically:YES]);
    NSDictionary *meta = @{
        @"database": @"testdb",
        @"applicationName": @"TestApp",
        @"applicationVersion": @"1.0.0",
        @"timestamp": @"2026-06-11T00:00:00Z",
        @"userSubmitted": @YES,
        kSessionIDKey: crashedSessionID.UUIDString,
    };
    XCTAssertTrue([meta writeToFile:metaPath atomically:YES]);

    // Upload service whose first network call fails synchronously.
    MockURLSession *mockSession = [[MockURLSession alloc] init];
    mockSession.nextError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
    BugSplatUploadService *uploadService = [[BugSplatUploadService alloc] initWithDatabase:@"testdb"
                                                                           applicationName:@"TestApp"
                                                                        applicationVersion:@"1.0.0"
                                                                                urlSession:mockSession];
    [uploadService setCompletionDispatcher:^(dispatch_block_t block) { block(); }];
    [self.bugSplat setUploadServiceForTesting:uploadService];

    SessionIDRecordingDelegate *delegate = [[SessionIDRecordingDelegate alloc] init];
    self.bugSplat.delegate = delegate;
    self.bugSplat.autoSubmitCrashReport = YES;

    [self.bugSplat processPendingCrashReports];

    XCTAssertTrue(delegate.willSendCallbackInvoked);
    XCTAssertEqualObjects(delegate.receivedWillSendSessionID, crashedSessionID,
                          @"willSend should carry the session ID recovered from the .meta file");
    XCTAssertTrue(delegate.didFailCallbackInvoked);
    XCTAssertEqualObjects(delegate.receivedDidFailSessionID, crashedSessionID,
                          @"didFail should carry the session ID so the app can keep its mapping for retry");
}

- (void)testSubmit_DeliversPersistedSessionIDToDidFinishSendingOnSuccess
{
    // Plant a crash + meta pair as if persisted at a previous launch. The name sorts
    // after any timestamp-based leftovers so processPendingCrashReports picks it.
    NSUUID *crashedSessionID = [NSUUID UUID];
    NSString *filename = @"99999999998";
    [self.filenamesToCleanup addObject:filename];

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *crashPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"crash"];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    XCTAssertTrue([[@"test crash report" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:crashPath atomically:YES]);
    NSDictionary *meta = @{
        @"database": @"testdb",
        @"applicationName": @"TestApp",
        @"applicationVersion": @"1.0.0",
        @"timestamp": @"2026-06-11T00:00:00Z",
        @"userSubmitted": @YES,
        kSessionIDKey: crashedSessionID.UUIDString,
    };
    XCTAssertTrue([meta writeToFile:metaPath atomically:YES]);

    // Upload service whose three-step flow (presign -> S3 -> commit) all succeed.
    MockURLSession *mockSession = [[MockURLSession alloc] init];
    NSData *presignJSON = [@"{\"url\":\"https://example.com/presigned\"}" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *commitJSON = [@"{\"crashId\":123,\"infoUrl\":\"https://example.com/crash/123\"}" dataUsingEncoding:NSUTF8StringEncoding];
    [mockSession queueResponseWithData:presignJSON response:[MockURLSession jsonResponseWithStatusCode:200] error:nil];
    [mockSession queueResponseWithData:nil response:[MockURLSession responseWithStatusCode:200] error:nil];
    [mockSession queueResponseWithData:commitJSON response:[MockURLSession jsonResponseWithStatusCode:200] error:nil];

    BugSplatUploadService *uploadService = [[BugSplatUploadService alloc] initWithDatabase:@"testdb"
                                                                           applicationName:@"TestApp"
                                                                        applicationVersion:@"1.0.0"
                                                                                urlSession:mockSession];
    [uploadService setCompletionDispatcher:^(dispatch_block_t block) { block(); }];
    [self.bugSplat setUploadServiceForTesting:uploadService];

    SessionIDRecordingDelegate *delegate = [[SessionIDRecordingDelegate alloc] init];
    self.bugSplat.delegate = delegate;
    self.bugSplat.autoSubmitCrashReport = YES;

    [self.bugSplat processPendingCrashReports];

    XCTAssertTrue(delegate.willSendCallbackInvoked);
    XCTAssertTrue(delegate.didFinishCallbackInvoked,
                  @"didFinishSending should fire after a successful upload");
    XCTAssertEqualObjects(delegate.receivedDidFinishSessionID, crashedSessionID,
                          @"didFinishSending should carry the session ID recovered from the .meta file "
                          @"so the app can clean up the crashed session's log");
    XCTAssertFalse(delegate.didFailCallbackInvoked, @"didFail should not fire on a successful upload");
}

#pragma mark - Hang enrichment tests

/// Plants a hang report (.crash + .meta with the -hang suffix) carrying the given
/// session ID, as persistHangReportWithDuration:appState: would at hang time.
- (NSString *)plantHangReportWithSessionID:(NSUUID *)sessionID
{
    NSString *filename = @"99999999997-hang";
    [self.filenamesToCleanup addObject:filename];

    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *crashPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"crash"];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    XCTAssertTrue([[@"App Hang (Fatal)" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:crashPath atomically:YES]);
    NSDictionary *meta = @{
        @"database": @"testdb",
        @"applicationName": @"TestApp",
        @"applicationVersion": @"1.0.0",
        @"timestamp": @"2026-06-11T00:00:00Z",
        @"userSubmitted": @YES,
        kSessionIDKey: sessionID.UUIDString,
    };
    XCTAssertTrue([meta writeToFile:metaPath atomically:YES]);
    return filename;
}

- (void)testEnrichPendingHangReports_AttachesSessionLogAndApplicationLog
{
    NSUUID *hangSessionID = [NSUUID UUID];
    NSString *filename = [self plantHangReportWithSessionID:hangSessionID];

    HangEnrichmentDelegate *delegate = [[HangEnrichmentDelegate alloc] init];
    self.bugSplat.delegate = delegate;

    [self.bugSplat enrichPendingHangReports];

    // The delegate was asked, with the HUNG session's ID — not the current one.
    XCTAssertEqual(delegate.attachmentCallCount, 1);
    XCTAssertEqualObjects(delegate.receivedAttachmentSessionID, hangSessionID,
                          @"Hang enrichment should pass the session that hung, recovered from .meta");
    XCTAssertNotEqualObjects(delegate.receivedAttachmentSessionID, self.bugSplat.sessionID);
    XCTAssertEqual(delegate.applicationLogCallCount, 1);
    XCTAssertEqualObjects(delegate.receivedApplicationLogSessionID, hangSessionID);

    NSString *dir = [self.bugSplat crashesDirectoryPath];

    // The attachment is persisted next to the report so the existing uploader picks it up.
    NSString *attachmentPath = [[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-0", filename]]
                                stringByAppendingPathExtension:@"data"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:attachmentPath],
                  @"Hang enrichment should persist the delegate attachment alongside the report");

    // The application log and the enriched marker were written into the .meta.
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
    XCTAssertEqualObjects(meta[@"applicationLog"], @"hang app log");
    XCTAssertEqualObjects(meta[@"hangEnriched"], @YES);
    // Pre-existing metadata must be preserved across the rewrite.
    XCTAssertEqualObjects(meta[kSessionIDKey], hangSessionID.UUIDString);
}

- (void)testEnrichPendingHangReports_IsIdempotentAcrossLaunches
{
    NSUUID *hangSessionID = [NSUUID UUID];
    [self plantHangReportWithSessionID:hangSessionID];

    HangEnrichmentDelegate *delegate = [[HangEnrichmentDelegate alloc] init];
    self.bugSplat.delegate = delegate;

    [self.bugSplat enrichPendingHangReports];
    [self.bugSplat enrichPendingHangReports];  // simulates a later offline-retry launch

    XCTAssertEqual(delegate.attachmentCallCount, 1,
                   @"An already-enriched hang report must not invoke the delegate again");
    XCTAssertEqual(delegate.applicationLogCallCount, 1);
}

- (void)testEnrichPendingHangReports_IgnoresNonHangReports
{
    // A regular crash report (no -hang suffix) must be left untouched — crashes are
    // enriched on the PLCrashReporter path, not here.
    NSString *filename = @"99999999996";
    [self.filenamesToCleanup addObject:filename];
    NSString *dir = [self.bugSplat crashesDirectoryPath];
    NSString *crashPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"crash"];
    NSString *metaPath = [[dir stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"meta"];
    XCTAssertTrue([[@"crash" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:crashPath atomically:YES]);
    XCTAssertTrue(([@{ kSessionIDKey: [NSUUID UUID].UUIDString } writeToFile:metaPath atomically:YES]));

    HangEnrichmentDelegate *delegate = [[HangEnrichmentDelegate alloc] init];
    self.bugSplat.delegate = delegate;

    [self.bugSplat enrichPendingHangReports];

    XCTAssertEqual(delegate.attachmentCallCount, 0,
                   @"Hang enrichment must only touch -hang reports, not crash reports");
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
    XCTAssertNil(meta[@"hangEnriched"]);
}

@end
