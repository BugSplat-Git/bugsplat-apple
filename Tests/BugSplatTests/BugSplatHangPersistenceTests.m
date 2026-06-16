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


@interface BugSplatHangPersistenceTests : XCTestCase
@property (nonatomic, strong) BugSplat *bugSplat;
@property (nonatomic, copy, nullable) NSString *filenameToCleanup;
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
