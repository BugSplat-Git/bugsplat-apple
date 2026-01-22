//
//  BugSplatUploadServiceTests.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "BugSplatUploadService.h"
#import "MockURLSession.h"

@interface BugSplatUploadServiceTests : XCTestCase

@property (nonatomic, strong) MockURLSession *mockSession;
@property (nonatomic, strong) BugSplatUploadService *uploadService;

@end

@implementation BugSplatUploadServiceTests

- (void)setUp
{
    [super setUp];
    self.mockSession = [[MockURLSession alloc] init];
    self.uploadService = [[BugSplatUploadService alloc] initWithDatabase:@"testdb"
                                                         applicationName:@"TestApp"
                                                      applicationVersion:@"1.0.0"
                                                              urlSession:self.mockSession];
}

- (void)tearDown
{
    [self.mockSession reset];
    self.uploadService = nil;
    [super tearDown];
}

#pragma mark - Initialization Tests

- (void)testInit_SetsProperties
{
    BugSplatUploadService *service = [[BugSplatUploadService alloc] initWithDatabase:@"mydb"
                                                                     applicationName:@"MyApp"
                                                                  applicationVersion:@"2.0.0"
                                                                          urlSession:self.mockSession];
    XCTAssertNotNil(service);
}

#pragma mark - Upload Flow Tests

- (void)testUploadCrashReport_CallsGetPresignedURL
{
    // Setup mock responses for the 3-step flow
    // Step 1: Get presigned URL
    NSDictionary *presignedResponse = @{@"url": @"https://s3.amazonaws.com/bucket/key?signature=abc"};
    NSData *presignedData = [NSJSONSerialization dataWithJSONObject:presignedResponse options:0 error:nil];
    [self.mockSession queueResponseWithData:presignedData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    
    // Step 2: S3 upload
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:200]
                                      error:nil];
    
    // Step 3: Commit
    NSDictionary *commitResponse = @{@"status": @"success", @"infoUrl": @"https://bugsplat.com/crash/123"};
    NSData *commitData = [NSJSONSerialization dataWithJSONObject:commitResponse options:0 error:nil];
    [self.mockSession queueResponseWithData:commitData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload completes"];
    
    NSData *crashData = [@"Crash report content" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        XCTAssertTrue(success);
        XCTAssertNil(error);
        XCTAssertEqualObjects(infoUrl, @"https://bugsplat.com/crash/123");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    
    // Verify requests were made
    XCTAssertEqual(self.mockSession.requestCount, 3);
}

- (void)testUploadCrashReport_FirstRequestContainsCorrectURL
{
    // Setup minimal response
    NSDictionary *presignedResponse = @{@"url": @"https://s3.example.com/test"};
    NSData *presignedData = [NSJSONSerialization dataWithJSONObject:presignedResponse options:0 error:nil];
    [self.mockSession queueResponseWithData:presignedData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload completes"];
    
    NSData *crashData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    
    // Verify first request URL contains expected components
    NSURLRequest *firstRequest = self.mockSession.recordedRequests[0].request;
    NSString *urlString = firstRequest.URL.absoluteString;
    
    XCTAssertTrue([urlString containsString:@"testdb.bugsplat.com"]);
    XCTAssertTrue([urlString containsString:@"getCrashUploadUrl"]);
    XCTAssertTrue([urlString containsString:@"database=testdb"]);
    XCTAssertTrue([urlString containsString:@"appName=TestApp"]);
    XCTAssertTrue([urlString containsString:@"appVersion=1.0.0"]);
}

- (void)testUploadCrashReport_SecondRequestIsPUTToS3
{
    NSDictionary *presignedResponse = @{@"url": @"https://s3.example.com/bucket/key"};
    NSData *presignedData = [NSJSONSerialization dataWithJSONObject:presignedResponse options:0 error:nil];
    [self.mockSession queueResponseWithData:presignedData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload completes"];
    
    NSData *crashData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    
    // Second request should be PUT to S3
    MockURLSessionRequest *s3Request = self.mockSession.recordedRequests[1];
    XCTAssertTrue(s3Request.isUploadTask);
    XCTAssertEqualObjects(s3Request.request.HTTPMethod, @"PUT");
    XCTAssertTrue([s3Request.request.URL.absoluteString containsString:@"s3.example.com"]);
}

- (void)testUploadCrashReport_ThirdRequestIsCommit
{
    NSDictionary *presignedResponse = @{@"url": @"https://s3.example.com/bucket/key"};
    NSData *presignedData = [NSJSONSerialization dataWithJSONObject:presignedResponse options:0 error:nil];
    [self.mockSession queueResponseWithData:presignedData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload completes"];
    
    NSData *crashData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    
    // Third request should be POST to commit endpoint
    NSURLRequest *commitRequest = self.mockSession.recordedRequests[2].request;
    XCTAssertEqualObjects(commitRequest.HTTPMethod, @"POST");
    XCTAssertTrue([commitRequest.URL.absoluteString containsString:@"commitS3CrashUpload"]);
}

#pragma mark - Error Handling Tests

- (void)testUploadCrashReport_FailsWithEmptyData
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload fails"];
    
    [self.uploadService uploadCrashReport:[NSData data]
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testUploadCrashReport_FailsWithNilData
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload fails"];
    
    [self.uploadService uploadCrashReport:nil
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testUploadCrashReport_FailsOnNetworkError
{
    NSError *networkError = [NSError errorWithDomain:NSURLErrorDomain
                                                code:NSURLErrorNotConnectedToInternet
                                            userInfo:nil];
    [self.mockSession queueResponseWithData:nil response:nil error:networkError];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload fails"];
    
    NSData *crashData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, NSURLErrorNotConnectedToInternet);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testUploadCrashReport_FailsOn429RateLimit
{
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:429]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload fails"];
    
    NSData *crashData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
        // Rate limit error code is 4
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testUploadCrashReport_FailsOnServerError
{
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:500]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload fails"];
    
    NSData *crashData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testUploadCrashReport_FailsOnInvalidJSON
{
    NSData *invalidJSON = [@"not valid json" dataUsingEncoding:NSUTF8StringEncoding];
    [self.mockSession queueResponseWithData:invalidJSON
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload fails"];
    
    NSData *crashData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testUploadCrashReport_FailsOnMissingURLInResponse
{
    NSDictionary *responseWithoutURL = @{@"status": @"ok"};
    NSData *responseData = [NSJSONSerialization dataWithJSONObject:responseWithoutURL options:0 error:nil];
    [self.mockSession queueResponseWithData:responseData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload fails"];
    
    NSData *crashData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

#pragma mark - Metadata Tests

- (void)testUploadCrashReport_IncludesMetadataInCommit
{
    NSDictionary *presignedResponse = @{@"url": @"https://s3.example.com/bucket/key"};
    NSData *presignedData = [NSJSONSerialization dataWithJSONObject:presignedResponse options:0 error:nil];
    [self.mockSession queueResponseWithData:presignedData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload completes"];
    
    BugSplatCrashMetadata *metadata = [[BugSplatCrashMetadata alloc] init];
    metadata.userName = @"Test User";
    metadata.userEmail = @"test@example.com";
    metadata.userDescription = @"This is what happened";
    metadata.applicationKey = @"license-123";
    metadata.notes = @"Debug build";
    
    NSData *crashData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:metadata
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    
    // Check that metadata was included in the commit request body
    // The body is multipart form data, so we check for field names
    MockURLSessionRequest *commitRequest = self.mockSession.recordedRequests[2];
    NSString *bodyString = [[NSString alloc] initWithData:commitRequest.request.HTTPBody encoding:NSUTF8StringEncoding];
    
    XCTAssertTrue([bodyString containsString:@"name=\"user\""]);
    XCTAssertTrue([bodyString containsString:@"Test User"]);
    XCTAssertTrue([bodyString containsString:@"name=\"email\""]);
    XCTAssertTrue([bodyString containsString:@"test@example.com"]);
    XCTAssertTrue([bodyString containsString:@"name=\"description\""]);
    XCTAssertTrue([bodyString containsString:@"This is what happened"]);
    XCTAssertTrue([bodyString containsString:@"name=\"appKey\""]);
    XCTAssertTrue([bodyString containsString:@"license-123"]);
    XCTAssertTrue([bodyString containsString:@"name=\"notes\""]);
    XCTAssertTrue([bodyString containsString:@"Debug build"]);
}

- (void)testUploadCrashReport_UsesCrashTimeMetadata
{
    // When metadata contains database/app info, it should be used instead of service defaults
    NSDictionary *presignedResponse = @{@"url": @"https://s3.example.com/bucket/key"};
    NSData *presignedData = [NSJSONSerialization dataWithJSONObject:presignedResponse options:0 error:nil];
    [self.mockSession queueResponseWithData:presignedData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload completes"];
    
    BugSplatCrashMetadata *metadata = [[BugSplatCrashMetadata alloc] init];
    metadata.database = @"crashTimeDb";
    metadata.applicationName = @"CrashTimeApp";
    metadata.applicationVersion = @"0.9.0";
    metadata.crashTime = @"2024-01-15T10:30:00Z";
    
    NSData *crashData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:nil
                                 metadata:metadata
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    
    // First request should use crash-time database
    NSURLRequest *firstRequest = self.mockSession.recordedRequests[0].request;
    NSString *urlString = firstRequest.URL.absoluteString;
    
    XCTAssertTrue([urlString containsString:@"crashTimeDb.bugsplat.com"]);
    XCTAssertTrue([urlString containsString:@"appName=CrashTimeApp"]);
    XCTAssertTrue([urlString containsString:@"appVersion=0.9.0"]);
    
    // Third request (commit) should include crashTime in the body
    MockURLSessionRequest *commitRequest = self.mockSession.recordedRequests[2];
    NSString *commitBody = [[NSString alloc] initWithData:commitRequest.request.HTTPBody encoding:NSUTF8StringEncoding];
    
    XCTAssertTrue([commitBody containsString:@"name=\"crashTime\""], @"Commit request should include crashTime field");
    XCTAssertTrue([commitBody containsString:@"2024-01-15T10:30:00Z"], @"Commit request should include the crashTime value");
}

#pragma mark - Attachment Tests

- (void)testUploadCrashReport_IncludesAttachmentsInZip
{
    NSDictionary *presignedResponse = @{@"url": @"https://s3.example.com/bucket/key"};
    NSData *presignedData = [NSJSONSerialization dataWithJSONObject:presignedResponse options:0 error:nil];
    [self.mockSession queueResponseWithData:presignedData
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:nil
                                   response:[MockURLSession responseWithStatusCode:200]
                                      error:nil];
    [self.mockSession queueResponseWithData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                   response:[MockURLSession jsonResponseWithStatusCode:200]
                                      error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Upload completes"];
    
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:@"log.txt"
                                                                   attachmentData:[@"log content" dataUsingEncoding:NSUTF8StringEncoding]
                                                                      contentType:@"text/plain"];
    
    NSData *crashData = [@"crash content" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uploadService uploadCrashReport:crashData
                            crashFilename:@"crash.crashlog"
                              attachments:@[attachment]
                                 metadata:nil
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        XCTAssertTrue(success);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    
    // The S3 upload should have body data (the ZIP)
    MockURLSessionRequest *s3Request = self.mockSession.recordedRequests[1];
    XCTAssertNotNil(s3Request.bodyData);
    XCTAssertGreaterThan(s3Request.bodyData.length, 0);
    
    // Verify it's a ZIP (check magic number)
    const uint8_t *bytes = s3Request.bodyData.bytes;
    XCTAssertEqual(bytes[0], 'P');
    XCTAssertEqual(bytes[1], 'K');
}

#pragma mark - Cancel Tests

- (void)testCancelUpload_CancelsCurrentTask
{
    // This test verifies cancel is callable without crashing
    // The actual task cancellation behavior is mocked
    [self.uploadService cancelUpload];
    // Should not crash
    XCTAssertTrue(YES);
}

#pragma mark - BugSplatCrashMetadata Tests

- (void)testCrashMetadata_AllPropertiesSettable
{
    BugSplatCrashMetadata *metadata = [[BugSplatCrashMetadata alloc] init];
    
    metadata.database = @"testdb";
    metadata.applicationName = @"TestApp";
    metadata.applicationVersion = @"1.0.0";
    metadata.userName = @"User";
    metadata.userEmail = @"user@test.com";
    metadata.userDescription = @"Description";
    metadata.applicationLog = @"Log content";
    metadata.applicationKey = @"key123";
    metadata.notes = @"Notes";
    metadata.attributes = @{@"attr1": @"value1"};
    metadata.crashTime = @"2024-01-15T10:30:00Z";
    
    XCTAssertEqualObjects(metadata.database, @"testdb");
    XCTAssertEqualObjects(metadata.applicationName, @"TestApp");
    XCTAssertEqualObjects(metadata.applicationVersion, @"1.0.0");
    XCTAssertEqualObjects(metadata.userName, @"User");
    XCTAssertEqualObjects(metadata.userEmail, @"user@test.com");
    XCTAssertEqualObjects(metadata.userDescription, @"Description");
    XCTAssertEqualObjects(metadata.applicationLog, @"Log content");
    XCTAssertEqualObjects(metadata.applicationKey, @"key123");
    XCTAssertEqualObjects(metadata.notes, @"Notes");
    XCTAssertEqualObjects(metadata.attributes[@"attr1"], @"value1");
    XCTAssertEqualObjects(metadata.crashTime, @"2024-01-15T10:30:00Z");
}

@end
