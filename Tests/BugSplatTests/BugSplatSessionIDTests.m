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
@property (nonatomic, assign) BOOL attachmentsCallbackInvoked;   // plural variant (macOS)
@property (nonatomic, assign) BOOL attachmentCallbackInvoked;    // singular variant
@property (nonatomic, assign) BOOL applicationLogCallbackInvoked;
@property (nonatomic, assign) BOOL willSendCallbackInvoked;
@property (nonatomic, assign) BOOL didFailCallbackInvoked;
@property (nonatomic, strong, nullable) NSUUID *receivedAttachmentSessionID;
@property (nonatomic, strong, nullable) NSUUID *receivedApplicationLogSessionID;
@property (nonatomic, strong, nullable) NSUUID *receivedWillSendSessionID;
@property (nonatomic, strong, nullable) NSUUID *receivedDidFailSessionID;
@end

@implementation SessionIDRecordingDelegate

#if TARGET_OS_OSX
- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    self.attachmentsCallbackInvoked = YES;
    self.receivedAttachmentSessionID = sessionID;
    return @[];
}
#endif

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

#if TARGET_OS_OSX
- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat
{
    self.legacyAttachmentsCallbackInvoked = YES;
    return @[];
}
#endif

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

#if TARGET_OS_OSX
- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat
{
    self.legacyAttachmentsCallbackInvoked = YES;
    return @[];
}
#endif

- (BugSplatAttachment *)attachmentForBugSplat:(BugSplat *)bugSplat
{
    self.legacyAttachmentCallbackInvoked = YES;
    return nil;
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

#if TARGET_OS_OSX
    XCTAssertTrue(delegate.attachmentsCallbackInvoked, @"plural sessionID-aware variant should be preferred on macOS");
    XCTAssertFalse(delegate.attachmentCallbackInvoked);
#else
    XCTAssertTrue(delegate.attachmentCallbackInvoked);
#endif
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

#if TARGET_OS_OSX
    XCTAssertTrue(delegate.attachmentsCallbackInvoked);
    XCTAssertFalse(delegate.legacyAttachmentsCallbackInvoked, @"Legacy variant should not be called when the sessionID-aware variant is implemented");
#else
    XCTAssertTrue(delegate.attachmentCallbackInvoked);
#endif
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

#if TARGET_OS_OSX
    XCTAssertTrue(delegate.legacyAttachmentsCallbackInvoked, @"Legacy delegates must keep working");
#else
    XCTAssertTrue(delegate.legacyAttachmentCallbackInvoked, @"Legacy delegates must keep working");
#endif
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

#if TARGET_OS_OSX
    XCTAssertTrue(delegate.attachmentsCallbackInvoked);
#else
    XCTAssertTrue(delegate.attachmentCallbackInvoked);
#endif
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

@end
