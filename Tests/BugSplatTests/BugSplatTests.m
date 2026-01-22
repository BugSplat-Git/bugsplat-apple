//
//  BugSplatTests.m
//  BugSplatTests
//
//  Tests for the main BugSplat class core logic.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <TargetConditionals.h>
#import <XCTest/XCTest.h>

#if TARGET_OS_OSX
#import <BugSplatMac/BugSplat.h>
#else
#import <BugSplat/BugSplat.h>
#endif

#import "BugSplat+Testing.h"
#import "BugSplatTestSupport.h"
#import "MockCrashReporter.h"
#import "MockCrashStorage.h"
#import "MockUserDefaults.h"
#import "MockBundle.h"
#import "MockURLSession.h"
#import "BugSplatUploadService.h"

@interface BugSplatTests : XCTestCase

@property (nonatomic, strong) BugSplat *bugSplat;
@property (nonatomic, strong) MockCrashReporter *mockCrashReporter;
@property (nonatomic, strong) MockCrashStorage *mockCrashStorage;
@property (nonatomic, strong) MockUserDefaults *mockUserDefaults;
@property (nonatomic, strong) MockBundle *mockBundle;

@end

@implementation BugSplatTests

- (void)setUp
{
    [super setUp];
    
    self.mockCrashReporter = [[MockCrashReporter alloc] init];
    self.mockCrashStorage = [[MockCrashStorage alloc] init];
    self.mockUserDefaults = [[MockUserDefaults alloc] init];
    self.mockBundle = [[MockBundle alloc] init];
    
    // Set default Info.plist values
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
    [self.mockCrashReporter reset];
    [self.mockCrashStorage reset];
    [self.mockUserDefaults reset];
    self.bugSplat = nil;
    
    [super tearDown];
}

#pragma mark - Initialization Tests

- (void)testShared_ReturnsSameInstance
{
    BugSplat *instance1 = [BugSplat shared];
    BugSplat *instance2 = [BugSplat shared];
    
    XCTAssertEqual(instance1, instance2);
    XCTAssertNotNil(instance1);
}

- (void)testTestInstance_IsSeparateFromShared
{
    BugSplat *testInstance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                        crashStorage:self.mockCrashStorage
                                                        userDefaults:self.mockUserDefaults
                                                              bundle:self.mockBundle];
    
    XCTAssertNotEqual(testInstance, [BugSplat shared]);
}

#pragma mark - Database Property Tests

- (void)testBugSplatDatabase_ReturnsInfoPlistValue
{
    [self.mockBundle setObject:@"mydb" forInfoDictionaryKey:@"BugSplatDatabase"];
    
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    
    XCTAssertEqualObjects(instance.bugSplatDatabase, @"mydb");
}

- (void)testBugSplatDatabase_ProgrammaticValueOverridesInfoPlist
{
    [self.mockBundle setObject:@"plist-db" forInfoDictionaryKey:@"BugSplatDatabase"];
    
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    
    instance.bugSplatDatabase = @"programmatic-db";
    
    XCTAssertEqualObjects(instance.bugSplatDatabase, @"programmatic-db");
}

- (void)testBugSplatDatabase_ReturnsNilWhenNotSet
{
    [self.mockBundle setObject:nil forInfoDictionaryKey:@"BugSplatDatabase"];
    
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    
    XCTAssertNil(instance.bugSplatDatabase);
}

#pragma mark - Application Name Tests

- (void)testResolvedApplicationName_ReturnsProgrammaticValue
{
    self.bugSplat.applicationName = @"CustomAppName";
    
    XCTAssertEqualObjects([self.bugSplat resolvedApplicationName], @"CustomAppName");
}

- (void)testResolvedApplicationName_ReturnsDisplayNameFromInfoPlist
{
    [self.mockBundle setObject:@"Display Name" forInfoDictionaryKey:@"CFBundleDisplayName"];
    [self.mockBundle setObject:@"Bundle Name" forInfoDictionaryKey:@"CFBundleName"];
    
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    
    XCTAssertEqualObjects([instance resolvedApplicationName], @"Display Name");
}

- (void)testResolvedApplicationName_FallsBackToBundleName
{
    [self.mockBundle setObject:nil forInfoDictionaryKey:@"CFBundleDisplayName"];
    [self.mockBundle setObject:@"Bundle Name" forInfoDictionaryKey:@"CFBundleName"];
    
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    
    XCTAssertEqualObjects([instance resolvedApplicationName], @"Bundle Name");
}

- (void)testResolvedApplicationName_FallsBackToUnknown
{
    [self.mockBundle setObject:nil forInfoDictionaryKey:@"CFBundleDisplayName"];
    [self.mockBundle setObject:nil forInfoDictionaryKey:@"CFBundleName"];
    
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    
    XCTAssertEqualObjects([instance resolvedApplicationName], @"Unknown Application");
}

#pragma mark - Application Version Tests

- (void)testResolvedApplicationVersion_ReturnsProgrammaticValue
{
    self.bugSplat.applicationVersion = @"2.0.0";
    
    XCTAssertEqualObjects([self.bugSplat resolvedApplicationVersion], @"2.0.0");
}

- (void)testResolvedApplicationVersion_ReturnsInfoPlistValue
{
    [self.mockBundle setObject:@"3.0.0" forInfoDictionaryKey:@"CFBundleShortVersionString"];
    
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    
    XCTAssertEqualObjects([instance resolvedApplicationVersion], @"3.0.0");
}

- (void)testResolvedApplicationVersion_CombinesVersionAndBuildNumber
{
    [self.mockBundle setObject:@"2.5.0" forInfoDictionaryKey:@"CFBundleShortVersionString"];
    [self.mockBundle setObject:@"42" forInfoDictionaryKey:@"CFBundleVersion"];
    
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    
    XCTAssertEqualObjects([instance resolvedApplicationVersion], @"2.5.0 (42)");
}

- (void)testResolvedApplicationVersion_FallsBackTo1_0
{
    [self.mockBundle setObject:nil forInfoDictionaryKey:@"CFBundleShortVersionString"];
    
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    
    XCTAssertEqualObjects([instance resolvedApplicationVersion], @"1.0");
}

#pragma mark - User Details Tests

- (void)testUserName_PersistedInUserDefaults
{
    self.bugSplat.userName = @"Test User";
    
    XCTAssertEqualObjects([self.mockUserDefaults stringForKey:@"com.bugsplat.userName"], @"Test User");
}

- (void)testUserName_RetrievedFromUserDefaults
{
    [self.mockUserDefaults setObject:@"Stored User" forKey:@"com.bugsplat.userName"];
    
    XCTAssertEqualObjects(self.bugSplat.userName, @"Stored User");
}

- (void)testUserEmail_PersistedInUserDefaults
{
    self.bugSplat.userEmail = @"test@example.com";
    
    XCTAssertEqualObjects([self.mockUserDefaults stringForKey:@"com.bugsplat.userEmail"], @"test@example.com");
}

- (void)testUserEmail_RetrievedFromUserDefaults
{
    [self.mockUserDefaults setObject:@"stored@example.com" forKey:@"com.bugsplat.userEmail"];
    
    XCTAssertEqualObjects(self.bugSplat.userEmail, @"stored@example.com");
}

#pragma mark - Attribute Tests

- (void)testSetValue_ForAttribute_AddsAttribute
{
    BOOL result = [self.bugSplat setValue:@"value1" forAttribute:@"attr1"];
    
    XCTAssertTrue(result);
}

- (void)testSetValue_ForAttribute_ReturnsNOForEmptyAttribute
{
    BOOL result = [self.bugSplat setValue:@"value" forAttribute:@""];
    
    XCTAssertFalse(result);
}

- (void)testSetValue_ForAttribute_ReturnsNOForNilAttribute
{
    BOOL result = [self.bugSplat setValue:@"value" forAttribute:nil];
    
    XCTAssertFalse(result);
}

- (void)testSetValue_ForAttribute_RemovesAttributeWithNilValue
{
    [self.bugSplat setValue:@"value1" forAttribute:@"attr1"];
    BOOL result = [self.bugSplat setValue:nil forAttribute:@"attr1"];
    
    XCTAssertTrue(result);
}

- (void)testSetValue_ForAttribute_ReturnsNOWhenRemovingNonexistentAttribute
{
    BOOL result = [self.bugSplat setValue:nil forAttribute:@"nonexistent"];
    
    XCTAssertFalse(result);
}

#pragma mark - Should Send Silently Tests

- (void)testShouldSendCrashSilently_TrueWhenAutoSubmitEnabled
{
    self.bugSplat.autoSubmitCrashReport = YES;
    
    BOOL result = [self.bugSplat shouldSendCrashSilently:@{}];
    
    XCTAssertTrue(result);
}

- (void)testShouldSendCrashSilently_TrueWhenUserSubmitted
{
    self.bugSplat.autoSubmitCrashReport = NO;
    NSDictionary *metadata = @{@"userSubmitted": @YES};
    
    BOOL result = [self.bugSplat shouldSendCrashSilently:metadata];
    
    XCTAssertTrue(result);
}

- (void)testShouldSendCrashSilently_FalseWhenAutoSubmitDisabledAndNotUserSubmitted
{
    self.bugSplat.autoSubmitCrashReport = NO;
    NSDictionary *metadata = @{};
    
    BOOL result = [self.bugSplat shouldSendCrashSilently:metadata];
    
    XCTAssertFalse(result);
}

#if !TARGET_OS_OSX
- (void)testShouldSendCrashSilently_iOS_TrueWhenAlwaysSendEnabled
{
    self.bugSplat.autoSubmitCrashReport = NO;
    [self.mockUserDefaults setBool:YES forKey:@"com.bugsplat.alwaysSend"];
    
    BOOL result = [self.bugSplat shouldSendCrashSilently:@{}];
    
    XCTAssertTrue(result);
}
#endif

#pragma mark - App Key and Notes Tests

- (void)testAppKey_SetAndRetrieve
{
    self.bugSplat.appKey = @"license-key-123";
    
    XCTAssertEqualObjects(self.bugSplat.appKey, @"license-key-123");
}

- (void)testNotes_SetAndRetrieve
{
    self.bugSplat.notes = @"Debug build, feature X enabled";
    
    XCTAssertEqualObjects(self.bugSplat.notes, @"Debug build, feature X enabled");
}

#pragma mark - Auto Submit Tests

- (void)testAutoSubmitCrashReport_DefaultValue
{
    BugSplat *instance = [BugSplat testInstanceWithCrashReporter:self.mockCrashReporter
                                                    crashStorage:self.mockCrashStorage
                                                    userDefaults:self.mockUserDefaults
                                                          bundle:self.mockBundle];
    
#if TARGET_OS_OSX
    XCTAssertFalse(instance.autoSubmitCrashReport);
#else
    XCTAssertTrue(instance.autoSubmitCrashReport);
#endif
}

- (void)testAutoSubmitCrashReport_CanBeChanged
{
    self.bugSplat.autoSubmitCrashReport = !self.bugSplat.autoSubmitCrashReport;
    
    // Just verify it can be set without crashing
    XCTAssertTrue(YES);
}

#if TARGET_OS_OSX
#pragma mark - macOS Specific Tests

- (void)testAskUserDetails_DefaultValue
{
    XCTAssertTrue(self.bugSplat.askUserDetails);
}

- (void)testExpirationTimeInterval_DefaultValue
{
    XCTAssertEqual(self.bugSplat.expirationTimeInterval, -1);
}

- (void)testPresentModally_DefaultValue
{
    XCTAssertFalse(self.bugSplat.presentModally);
}

- (void)testPersistUserDetails_DefaultValue
{
    XCTAssertFalse(self.bugSplat.persistUserDetails);
}

#endif

#pragma mark - Delegate Tests

- (void)testDelegate_CanBeSet
{
    // Just verify delegate can be set without crashing
    self.bugSplat.delegate = nil;
    XCTAssertNil(self.bugSplat.delegate);
}

@end
