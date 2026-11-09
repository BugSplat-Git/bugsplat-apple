//
//  BugSplatPerAppCrashDirectoryTests.m
//  BugSplatTests
//
//  Tests that each app only sees its own persisted reports (issue #90). Non-sandboxed macOS
//  apps share one Application Support folder, and earlier SDK versions kept every app's
//  reports in a single BugSplat/Crashes folder inside it, so one app showed a dialog for, and
//  uploaded, another app's crash.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#include <stdlib.h>

#import <BugSplat/BugSplat.h>

#import "BugSplat+Testing.h"
#import "BugSplatTestSupport.h"
#import "BugSplatTestCrashDirectory.h"
#import "MockCrashReporter.h"
#import "MockCrashStorage.h"
#import "MockUserDefaults.h"
#import "MockBundle.h"

// Keys shared with BugSplat.m, duplicated as in the other test classes.
static NSString *const kBundleIdentifierKey = @"bundleIdentifier";
static NSString *const kDatabaseKey = @"database";
static NSString *const kApplicationNameKey = @"applicationName";
static NSString *const kUserSubmittedKey = @"userSubmitted";

static NSString *const kThisBundleIdentifier = @"com.bugsplat.tests.thisapp";

@interface BugSplatPerAppCrashDirectoryTests : XCTestCase
@property (nonatomic, strong) BugSplat *bugSplat;
@property (nonatomic, strong) MockBundle *mockBundle;
@property (nonatomic, copy) NSString *crashesDirectory;
@property (nonatomic, copy) NSString *legacyDirectory;
@end

@implementation BugSplatPerAppCrashDirectoryTests

- (void)setUp
{
    [super setUp];

    self.mockBundle = [[MockBundle alloc] init];
    [self.mockBundle setObject:kThisBundleIdentifier forInfoDictionaryKey:@"CFBundleIdentifier"];
    [self.mockBundle setObject:@"TestApp" forInfoDictionaryKey:@"CFBundleName"];
    [self.mockBundle setObject:@"1.0.0" forInfoDictionaryKey:@"CFBundleShortVersionString"];
    [self.mockBundle setObject:@"testdb" forInfoDictionaryKey:@"BugSplatDatabase"];

    self.bugSplat = [BugSplat testInstanceWithCrashReporter:[[MockCrashReporter alloc] init]
                                               crashStorage:[[MockCrashStorage alloc] init]
                                               userDefaults:[[MockUserDefaults alloc] init]
                                                     bundle:self.mockBundle];

    self.crashesDirectory = BugSplatTestsMakeIsolatedCrashesDirectory();
    self.legacyDirectory = BugSplatTestsMakeIsolatedCrashesDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:self.legacyDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [self.bugSplat setCrashesDirectoryPathOverride:self.crashesDirectory];
    [self.bugSplat setLegacyCrashesDirectoryPathOverride:self.legacyDirectory];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.crashesDirectory error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:self.legacyDirectory error:nil];
    self.bugSplat = nil;
    [super tearDown];
}

#pragma mark - Helpers

/// Writes <baseName>.crash, <baseName>.meta (when metadata is non-nil) and attachmentCount
/// <baseName>-N.data files into directory.
- (void)plantReport:(NSString *)baseName
        inDirectory:(NSString *)directory
           metadata:(nullable NSDictionary *)metadata
    attachmentCount:(NSUInteger)attachmentCount
{
    NSString *base = [directory stringByAppendingPathComponent:baseName];
    [[@"crash report text" dataUsingEncoding:NSUTF8StringEncoding]
        writeToFile:[base stringByAppendingPathExtension:@"crash"] atomically:YES];
    if (metadata) {
        [metadata writeToFile:[base stringByAppendingPathExtension:@"meta"] atomically:YES];
    }
    for (NSUInteger i = 0; i < attachmentCount; i++) {
        [[@"attachment" dataUsingEncoding:NSUTF8StringEncoding]
            writeToFile:[NSString stringWithFormat:@"%@-%lu.data", base, (unsigned long)i] atomically:YES];
    }
}

/// The report files in directory, sorted. Hidden files, such as the migration lock, are left out.
- (NSArray<NSString *> *)sortedContentsOfDirectory:(NSString *)directory
{
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] ?: @[];
    files = [files filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT SELF BEGINSWITH '.'"]];
    return [files sortedArrayUsingSelector:@selector(compare:)];
}

- (NSDictionary *)legacyMetadataWithDatabase:(NSString *)database applicationName:(NSString *)applicationName
{
    // The keys a .meta written before the fix carries - no bundle identifier
    return @{
        kApplicationNameKey: applicationName,
        @"applicationVersion": @"1.0 (1)",
        @"attributes": @{},
        kDatabaseKey: database,
        @"sessionID": [NSUUID UUID].UUIDString,
        @"timestamp": @"2026-10-01T12:00:00Z",
    };
}

#pragma mark - Directory layout

- (void)testDefaultCrashesDirectory_IsScopedByBundleIdentifier
{
    NSString *expectedSuffix = [NSString stringWithFormat:@"BugSplat/%@/Crashes", kThisBundleIdentifier];
    XCTAssertTrue([[self.bugSplat defaultCrashesDirectoryPath] hasSuffix:expectedSuffix],
                  @"Got %@", [self.bugSplat defaultCrashesDirectoryPath]);
}

- (void)testAppStorageIdentifier_WithoutBundleIdentifier_FallsBackToProcessName
{
    [self.mockBundle setObject:nil forInfoDictionaryKey:@"CFBundleIdentifier"];

    NSString *processName = [NSString stringWithUTF8String:getprogname()];
    XCTAssertEqualObjects([self.bugSplat appStorageIdentifier], processName);
    NSString *expectedSuffix = [NSString stringWithFormat:@"BugSplat/%@/Crashes", processName];
    XCTAssertTrue([[self.bugSplat defaultCrashesDirectoryPath] hasSuffix:expectedSuffix]);
}

- (void)testCrashesDirectoryOverride_StillWins
{
    XCTAssertEqualObjects([self.bugSplat crashesDirectoryPath], self.crashesDirectory);
}

#pragma mark - Legacy shared folder

- (void)testAnotherAppsReportInLegacyFolder_IsIgnoredAndLeftInPlace
{
    // The report from the issue: another app, which happens to share this app's database
    [self plantReport:@"811958543"
          inDirectory:self.legacyDirectory
             metadata:[self legacyMetadataWithDatabase:@"testdb" applicationName:@"BugSplatTest-macOS-UIKit-ObjC"]
      attachmentCount:1];
    // Another vendor's app entirely
    [self plantReport:@"811958600"
          inDirectory:self.legacyDirectory
             metadata:[self legacyMetadataWithDatabase:@"otherdb" applicationName:@"TestApp"]
      attachmentCount:0];
    // A hang report whose .meta holds only userSubmitted, so it cannot be attributed
    [self plantReport:@"811958543123-hang"
          inDirectory:self.legacyDirectory
             metadata:@{kUserSubmittedKey: @YES}
      attachmentCount:1];
    // An orphaned hang .meta / .data pair with no .crash
    [@{kUserSubmittedKey: @YES} writeToFile:[self.legacyDirectory stringByAppendingPathComponent:@"811958999000-hang.meta"]
                                 atomically:YES];
    [[@"attachment" dataUsingEncoding:NSUTF8StringEncoding]
        writeToFile:[self.legacyDirectory stringByAppendingPathComponent:@"811958999000-hang-0.data"] atomically:YES];

    NSArray *legacyBefore = [self sortedContentsOfDirectory:self.legacyDirectory];

    [self.bugSplat migrateLegacyCrashReports];

    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.legacyDirectory], legacyBefore,
                          @"Files another app owns, or that cannot be attributed, must not be moved or deleted");
    XCTAssertEqualObjects([self.bugSplat getPendingCrashFiles], @[]);
    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.crashesDirectory], @[]);

    // Declining for this app must not discard anything in the legacy folder either
    [self.bugSplat cleanupAllPendingCrashReports];
    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.legacyDirectory], legacyBefore);
}

- (void)testMatchingLegacyReport_IsMigratedWithItsAttachments
{
    NSDictionary *legacyMetadata = [self legacyMetadataWithDatabase:@"testdb" applicationName:@"TestApp"];
    [self plantReport:@"811958543" inDirectory:self.legacyDirectory metadata:legacyMetadata attachmentCount:2];
    // A hang report from another app whose name shares the crash's prefix must stay behind
    [self plantReport:@"811958543-hang"
          inDirectory:self.legacyDirectory
             metadata:[self legacyMetadataWithDatabase:@"hangtestdb" applicationName:@"HangTest"]
      attachmentCount:1];

    [self.bugSplat migrateLegacyCrashReports];

    NSArray *expectedMoved = @[@"811958543-0.data", @"811958543-1.data", @"811958543.crash", @"811958543.meta"];
    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.crashesDirectory], expectedMoved);
    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.legacyDirectory],
                          (@[@"811958543-hang-0.data", @"811958543-hang.crash", @"811958543-hang.meta"]));

    NSDictionary *migratedMetadata = [NSDictionary dictionaryWithContentsOfFile:
                                      [self.crashesDirectory stringByAppendingPathComponent:@"811958543.meta"]];
    XCTAssertEqualObjects(migratedMetadata[kBundleIdentifierKey], kThisBundleIdentifier,
                          @"An adopted report is stamped with this app's identifier");
    XCTAssertEqualObjects(migratedMetadata[kDatabaseKey], @"testdb");
    XCTAssertEqualObjects(migratedMetadata[kApplicationNameKey], @"TestApp");

    XCTAssertEqualObjects([self.bugSplat getPendingCrashFiles], @[@"811958543"]);
}

- (void)testLegacyReportNamingAnotherBundleIdentifier_IsNotMigrated
{
    NSMutableDictionary *metadata = [[self legacyMetadataWithDatabase:@"testdb" applicationName:@"TestApp"] mutableCopy];
    metadata[kBundleIdentifierKey] = @"com.example.someoneelse";
    [self plantReport:@"811958543" inDirectory:self.legacyDirectory metadata:metadata attachmentCount:0];

    [self.bugSplat migrateLegacyCrashReports];

    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.legacyDirectory],
                          (@[@"811958543.crash", @"811958543.meta"]));
    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.crashesDirectory], @[]);
}

- (void)testLegacyReportNameCollision_LeavesBothReportsAlone
{
    NSDictionary *legacyMetadata = [self legacyMetadataWithDatabase:@"testdb" applicationName:@"TestApp"];
    [self plantReport:@"811958543" inDirectory:self.legacyDirectory metadata:legacyMetadata attachmentCount:0];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.crashesDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [self plantReport:@"811958543"
          inDirectory:self.crashesDirectory
             metadata:@{kBundleIdentifierKey: kThisBundleIdentifier, kDatabaseKey: @"testdb"}
      attachmentCount:0];

    [self.bugSplat migrateLegacyCrashReports];

    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.legacyDirectory],
                          (@[@"811958543.crash", @"811958543.meta"]));
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:
                              [self.crashesDirectory stringByAppendingPathComponent:@"811958543.meta"]];
    XCTAssertNil(existing[kApplicationNameKey], @"The report already in the per-app folder must not be overwritten");
}

- (void)testLegacyMigrationStoppedPartWay_IsResumed
{
    // A previous launch wrote the stamped .meta and moved one attachment, then stopped before the .crash
    NSDictionary *legacyMetadata = [self legacyMetadataWithDatabase:@"testdb" applicationName:@"TestApp"];
    [self plantReport:@"811958543" inDirectory:self.legacyDirectory metadata:legacyMetadata attachmentCount:2];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.crashesDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:[self.legacyDirectory stringByAppendingPathComponent:@"811958543-0.data"]
                                            toPath:[self.crashesDirectory stringByAppendingPathComponent:@"811958543-0.data"]
                                             error:nil];
    [@{kBundleIdentifierKey: kThisBundleIdentifier} writeToFile:[self.crashesDirectory stringByAppendingPathComponent:@"811958543.meta"]
                                                     atomically:YES];
    XCTAssertEqualObjects([self.bugSplat getPendingCrashFiles], @[], @"No .crash yet, so nothing is pending");

    [self.bugSplat migrateLegacyCrashReports];

    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.crashesDirectory],
                          (@[@"811958543-0.data", @"811958543-1.data", @"811958543.crash", @"811958543.meta"]));
    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.legacyDirectory], @[]);
    NSDictionary *migratedMetadata = [NSDictionary dictionaryWithContentsOfFile:
                                      [self.crashesDirectory stringByAppendingPathComponent:@"811958543.meta"]];
    XCTAssertEqualObjects(migratedMetadata[kApplicationNameKey], @"TestApp", @"The full legacy metadata is carried over");
    XCTAssertEqualObjects(migratedMetadata[kBundleIdentifierKey], kThisBundleIdentifier);
}

- (void)testLegacyMigration_ReleasesItsLockForTheNextMigration
{
    NSDictionary *legacyMetadata = [self legacyMetadataWithDatabase:@"testdb" applicationName:@"TestApp"];
    [self plantReport:@"811958543" inDirectory:self.legacyDirectory metadata:legacyMetadata attachmentCount:1];
    [self.bugSplat migrateLegacyCrashReports];

    NSString *lockPath = [self.crashesDirectory stringByAppendingPathComponent:@".migration.lock"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:lockPath]);
    XCTAssertEqualObjects([self.bugSplat getPendingCrashFiles], @[@"811958543"], @"The lock file is not a report");

    // A second migration, with the lock file still there, isn't blocked by the first
    [self plantReport:@"811958600" inDirectory:self.legacyDirectory metadata:legacyMetadata attachmentCount:1];
    [self.bugSplat migrateLegacyCrashReports];

    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.legacyDirectory], @[]);
    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.crashesDirectory],
                          (@[@"811958543-0.data", @"811958543.crash", @"811958543.meta",
                             @"811958600-0.data", @"811958600.crash", @"811958600.meta"]));
}

#pragma mark - Attachments

- (void)testCrashAttachments_ExcludeASameNamedHangReport
{
    [[NSFileManager defaultManager] createDirectoryAtPath:self.crashesDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSData *data = [@"log" dataUsingEncoding:NSUTF8StringEncoding];
    [self.bugSplat persistAttachments:@[[[BugSplatAttachment alloc] initWithFilename:@"crash.log" attachmentData:data contentType:@"text/plain"]]
                     forCrashFilename:@"100"];
    [self.bugSplat persistAttachments:@[[[BugSplatAttachment alloc] initWithFilename:@"hang.log" attachmentData:data contentType:@"text/plain"]]
                     forCrashFilename:@"100-hang"];

    NSArray<BugSplatAttachment *> *loaded = [self.bugSplat loadPersistedAttachmentsForCrashFilename:@"100"];
    XCTAssertEqualObjects([loaded valueForKey:@"filename"], @[@"crash.log"]);

    [self.bugSplat cleanupCrashReportWithFilename:@"100"];
    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.crashesDirectory], @[@"100-hang-0.data"],
                          @"Cleaning up crash 100 must leave hang report 100-hang's attachment");
}

#pragma mark - Bundle identifier in .meta

- (void)testReportNamingAnotherBundleIdentifier_IsSkippedAndNeverTouched
{
    [[NSFileManager defaultManager] createDirectoryAtPath:self.crashesDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSDictionary *foreignMetadata = @{kBundleIdentifierKey: @"com.example.otherapp", kDatabaseKey: @"testdb"};
    [self plantReport:@"100" inDirectory:self.crashesDirectory metadata:foreignMetadata attachmentCount:1];
    [self plantReport:@"200"
          inDirectory:self.crashesDirectory
             metadata:@{kBundleIdentifierKey: kThisBundleIdentifier, kDatabaseKey: @"testdb"}
      attachmentCount:0];
    // A report without the key (adopted from an older SDK, say) still counts as this app's
    [self plantReport:@"300"
          inDirectory:self.crashesDirectory
             metadata:[self legacyMetadataWithDatabase:@"testdb" applicationName:@"TestApp"]
      attachmentCount:0];

    XCTAssertEqualObjects([self.bugSplat getPendingCrashFiles], (@[@"200", @"300"]));

    // Accepting the dialog for this app must not stamp another app's report as approved...
    [self.bugSplat markAllPendingCrashesAsSubmittedWithUserName:@"name" userEmail:@"email" exceptFilename:@"300"];
    NSDictionary *foreignAfterMark = [NSDictionary dictionaryWithContentsOfFile:
                                      [self.crashesDirectory stringByAppendingPathComponent:@"100.meta"]];
    XCTAssertEqualObjects(foreignAfterMark, foreignMetadata);

    // ...and declining it must not discard another app's report
    [self.bugSplat cleanupAllPendingCrashReports];
    XCTAssertEqualObjects([self sortedContentsOfDirectory:self.crashesDirectory],
                          (@[@"100-0.data", @"100.crash", @"100.meta"]));
}

- (void)testMarkingReportSubmitted_RecordsBundleIdentifier
{
    [[NSFileManager defaultManager] createDirectoryAtPath:self.crashesDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [self plantReport:@"100" inDirectory:self.crashesDirectory metadata:nil attachmentCount:0];
    [self plantReport:@"200" inDirectory:self.crashesDirectory metadata:nil attachmentCount:0];

    [self.bugSplat markAllPendingCrashesAsSubmittedWithUserName:nil userEmail:nil exceptFilename:@"200"];

    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:
                              [self.crashesDirectory stringByAppendingPathComponent:@"100.meta"]];
    XCTAssertEqualObjects(metadata[kBundleIdentifierKey], kThisBundleIdentifier);
    XCTAssertEqualObjects(metadata[kUserSubmittedKey], @YES);
}

- (void)testNewHangReport_RecordsBundleIdentifier
{
    // A regular instance carries the real PLCrashReporter the live hang capture needs
    BugSplat *bugSplat = [[BugSplat alloc] init];
    bugSplat.bugSplatDatabase = @"testdb";
    bugSplat.applicationName = @"TestApp";
    bugSplat.enableHangDetection = YES;
    [bugSplat setupHangInfrastructureForTesting];
    [bugSplat setCrashesDirectoryPathOverride:self.crashesDirectory];

    [bugSplat hangTracker:nil didDetectHangWithDuration:2.0 appState:@"active"];
    dispatch_sync([bugSplat hangQueueForTesting], ^{});

    NSString *filename = [bugSplat currentHangFilename];
    XCTAssertNotNil(filename);
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:
                              [[self.crashesDirectory stringByAppendingPathComponent:filename]
                               stringByAppendingPathExtension:@"meta"]];
    XCTAssertNotNil(metadata[kBundleIdentifierKey]);
    XCTAssertEqualObjects(metadata[kBundleIdentifierKey], [bugSplat appStorageIdentifier]);
}

@end
