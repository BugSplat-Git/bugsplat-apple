//
//  BugSplatUploadService.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BugSplatUploadService.h"
#import "BugSplatZipHelper.h"
#import "BugSplatTestSupport.h"

NSString *const BugSplatUploadErrorDomain = @"com.bugsplat.upload";

typedef NS_ENUM(NSInteger, BugSplatUploadErrorCode) {
    BugSplatUploadErrorCodeInvalidData = 1,
    BugSplatUploadErrorCodeNetworkError = 2,
    BugSplatUploadErrorCodeServerError = 3,
    BugSplatUploadErrorCodeRateLimited = 4,
    BugSplatUploadErrorCodeCancelled = 5
};

@implementation BugSplatCrashMetadata
@end

@interface BugSplatUploadService ()

@property (nonatomic, copy) NSString *database;
@property (nonatomic, copy) NSString *applicationName;
@property (nonatomic, copy) NSString *applicationVersion;
@property (nonatomic, strong) id<BugSplatURLSessionProtocol> urlSession;
@property (nonatomic, strong, nullable) NSURLSessionTask *currentTask;

// Delivers completion handlers (default: async on the main queue). Private;
// exposed to tests via BugSplatUploadService+Testing.h so they can inject a
// synchronous dispatcher. See -deliverCompletion:.
@property (nonatomic, copy) void (^completionDispatcher)(dispatch_block_t block);

@end

@implementation BugSplatUploadService

- (instancetype)initWithDatabase:(NSString *)database
                 applicationName:(NSString *)applicationName
              applicationVersion:(NSString *)applicationVersion
{
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 60.0;
    config.timeoutIntervalForResource = 300.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    return [self initWithDatabase:database
                  applicationName:applicationName
               applicationVersion:applicationVersion
                       urlSession:(id<BugSplatURLSessionProtocol>)session];
}

- (instancetype)initWithDatabase:(NSString *)database
                 applicationName:(NSString *)applicationName
              applicationVersion:(NSString *)applicationVersion
                      urlSession:(id<BugSplatURLSessionProtocol>)urlSession
{
    self = [super init];
    if (self) {
        _database = [database copy];
        _applicationName = [applicationName copy];
        _applicationVersion = [applicationVersion copy];
        _urlSession = urlSession;
        // Production always delivers completions asynchronously on the main
        // thread. Tests may override this with a synchronous dispatcher so the
        // multi-step upload flow completes without depending on the run loop.
        _completionDispatcher = ^(dispatch_block_t block) {
            dispatch_async(dispatch_get_main_queue(), block);
        };
    }
    return self;
}

- (void)dealloc
{
    [_urlSession invalidateAndCancel];
}

/// Routes a completion block through the configured dispatcher (async-on-main in
/// production). Falls back to async-on-main if a caller nils out the dispatcher.
- (void)deliverCompletion:(dispatch_block_t)block
{
    if (self.completionDispatcher) {
        self.completionDispatcher(block);
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

- (void)uploadCrashReport:(NSData *)crashData
            crashFilename:(NSString *)crashFilename
              attachments:(NSArray<BugSplatAttachment *> *)attachments
                 metadata:(BugSplatCrashMetadata *)metadata
               completion:(BugSplatUploadCompletion)completion
{
    // Defensive: ensure completion is not nil
    if (!completion) {
        NSLog(@"BugSplat: uploadCrashReport called with nil completion handler");
        return;
    }
    
    @try {
        if (!crashData || crashData.length == 0) {
            NSError *error = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                 code:BugSplatUploadErrorCodeInvalidData
                                             userInfo:@{NSLocalizedDescriptionKey: @"Crash data is empty"}];
            completion(NO, error, nil, nil);
            return;
        }
        
        // Use crash-time values from metadata, fall back to upload service defaults
        NSString *database = metadata.database ?: self.database;
        NSString *appName = metadata.applicationName ?: self.applicationName;
        NSString *appVersion = metadata.applicationVersion ?: self.applicationVersion;
        
        // Create ZIP archive with crash data and attachments
        NSMutableArray<BugSplatZipEntry *> *zipEntries = [NSMutableArray array];
        
        // Add crash data as the primary file
        [zipEntries addObject:[BugSplatZipEntry entryWithFilename:crashFilename ?: @"crash.crashlog" data:crashData]];
        
        // Add all attachments to the ZIP (wrapped to prevent crashes from bad attachments)
        for (BugSplatAttachment *attachment in attachments) {
            @try {
                if (attachment && attachment.attachmentData && attachment.filename) {
                    [zipEntries addObject:[BugSplatZipEntry entryWithFilename:attachment.filename data:attachment.attachmentData]];
                    NSLog(@"BugSplat: Adding attachment to ZIP: %@", attachment.filename);
                }
            } @catch (NSException *exception) {
                NSLog(@"BugSplat: Exception adding attachment to ZIP: %@ - %@", exception.name, exception.reason);
                // Continue with remaining attachments
            }
        }
        
        NSData *zipData = [BugSplatZipHelper zipEntries:zipEntries];
        if (!zipData) {
            NSError *error = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                 code:BugSplatUploadErrorCodeInvalidData
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to create ZIP archive"}];
            completion(NO, error, nil, nil);
            return;
        }
        
        NSString *md5Hash = [BugSplatZipHelper md5HashOfData:zipData];
    
        // Step 1: Get presigned URL (using crash-time values)
        [self getPresignedURLForDatabase:database
                         applicationName:appName
                      applicationVersion:appVersion
                                    size:zipData.length
                              completion:^(NSString *presignedURL, NSError *error) {
            if (error) {
                completion(NO, error, nil, nil);
                return;
            }
            
            // Step 2: Upload to S3
            [self uploadData:zipData toPresignedURL:presignedURL completion:^(BOOL success, NSError *uploadError) {
                if (!success) {
                    completion(NO, uploadError, nil, nil);
                    return;
                }
                
                // Step 3: Commit the upload (using crash-time values)
                [self commitUploadWithS3Key:presignedURL
                                    md5Hash:md5Hash
                                   database:database
                            applicationName:appName
                         applicationVersion:appVersion
                                   metadata:metadata
                                 completion:completion];
            }];
        }];
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in uploadCrashReport: %@ - %@", exception.name, exception.reason);
        NSError *error = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                             code:BugSplatUploadErrorCodeInvalidData
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Exception: %@", exception.reason]}];
        completion(NO, error, nil, nil);
    }
}

- (void)uploadFeedback:(NSString *)title
           description:(NSString *)description
           attachments:(NSArray<BugSplatAttachment *> *)attachments
              metadata:(BugSplatCrashMetadata *)metadata
            completion:(BugSplatFeedbackUploadCompletion)completion
{
    // Substitute a no-op block so the upload proceeds even without a caller-supplied completion
    BugSplatFeedbackUploadCompletion safeCompletion = completion ?: ^(BugSplatFeedbackResult * _Nullable __unused result, NSError * _Nullable __unused error) {};

    @try {
        // Validate that title is non-nil and non-empty
        if (!title || title.length == 0) {
            NSError *error = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                 code:BugSplatUploadErrorCodeInvalidData
                                             userInfo:@{NSLocalizedDescriptionKey: @"Feedback title is required and cannot be empty"}];
            safeCompletion(nil, error);
            return;
        }

        metadata.crashTypeId = @"36";

        // Create feedback.json content
        NSMutableDictionary *feedbackDict = [NSMutableDictionary dictionary];
        feedbackDict[@"title"] = title;
        feedbackDict[@"description"] = description ?: @"";

        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:feedbackDict options:0 error:&jsonError];
        if (jsonError) {
            safeCompletion(nil, jsonError);
            return;
        }

        // Create zip entries starting with feedback.json
        NSMutableArray<BugSplatZipEntry *> *zipEntries = [NSMutableArray array];
        [zipEntries addObject:[BugSplatZipEntry entryWithFilename:@"feedback.json" data:jsonData]];

        // Add all attachments to the ZIP (same pattern as crash report uploads)
        for (BugSplatAttachment *attachment in attachments) {
            @try {
                if (attachment && attachment.attachmentData && attachment.filename) {
                    [zipEntries addObject:[BugSplatZipEntry entryWithFilename:attachment.filename data:attachment.attachmentData]];
                    NSLog(@"BugSplat: Adding attachment to feedback ZIP: %@", attachment.filename);
                }
            } @catch (NSException *exception) {
                NSLog(@"BugSplat: Exception adding attachment to feedback ZIP: %@ - %@", exception.name, exception.reason);
                // Continue with remaining attachments
            }
        }

        NSData *zipData = [BugSplatZipHelper zipEntries:zipEntries];
        if (!zipData) {
            NSError *error = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                 code:BugSplatUploadErrorCodeInvalidData
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to create feedback ZIP archive"}];
            safeCompletion(nil, error);
            return;
        }

        // Use crash-time values from metadata, fall back to upload service defaults
        NSString *database = metadata.database ?: self.database;
        NSString *appName = metadata.applicationName ?: self.applicationName;
        NSString *appVersion = metadata.applicationVersion ?: self.applicationVersion;

        NSString *md5Hash = [BugSplatZipHelper md5HashOfData:zipData];

        // Step 1: Get presigned URL
        [self getPresignedURLForDatabase:database
                         applicationName:appName
                      applicationVersion:appVersion
                                    size:zipData.length
                              completion:^(NSString *presignedURL, NSError *error) {
            if (error) {
                safeCompletion(nil, error);
                return;
            }

            // Step 2: Upload to S3
            [self uploadData:zipData toPresignedURL:presignedURL completion:^(BOOL success, NSError *uploadError) {
                if (!success) {
                    safeCompletion(nil, uploadError);
                    return;
                }

                // Step 3: Commit the upload
                [self commitUploadWithS3Key:presignedURL
                                    md5Hash:md5Hash
                                   database:database
                            applicationName:appName
                         applicationVersion:appVersion
                                   metadata:metadata
                                 completion:^(BOOL commitSuccess, NSError *commitError, NSString *infoUrl, NSNumber *crashId) {
                    if (commitSuccess) {
                        NSLog(@"BugSplat: User feedback uploaded successfully");
                        BugSplatFeedbackResult *result = [[BugSplatFeedbackResult alloc] initWithCrashId:crashId
                                                                                                 infoUrl:infoUrl];
                        safeCompletion(result, nil);
                    } else {
                        safeCompletion(nil, commitError);
                    }
                }];
            }];
        }];
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in uploadFeedback: %@ - %@", exception.name, exception.reason);
        NSError *error = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                             code:BugSplatUploadErrorCodeInvalidData
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Exception: %@", exception.reason]}];
        safeCompletion(nil, error);
    }
}

- (void)cancelUpload
{
    [self.currentTask cancel];
    self.currentTask = nil;
}

#pragma mark - Step 1: Get Presigned URL

- (void)getPresignedURLForDatabase:(NSString *)database
                   applicationName:(NSString *)appName
                applicationVersion:(NSString *)appVersion
                              size:(NSUInteger)size
                        completion:(void(^)(NSString * _Nullable url, NSError * _Nullable error))completion
{
    NSString *urlString = [NSString stringWithFormat:
        @"https://%@.bugsplat.com/api/getCrashUploadUrl?database=%@&appName=%@&appVersion=%@&crashPostSize=%lu",
        database,
        [self urlEncode:database],
        [self urlEncode:appName],
        [self urlEncode:appVersion],
        (unsigned long)size];
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                             code:BugSplatUploadErrorCodeInvalidData
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
        completion(nil, error);
        return;
    }
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    self.currentTask = [self.urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self deliverCompletion:^{
                completion(nil, error);
            }];
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if (httpResponse.statusCode == 429) {
            NSError *rateLimitError = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                          code:BugSplatUploadErrorCodeRateLimited
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Too many requests"}];
            [self deliverCompletion:^{
                completion(nil, rateLimitError);
            }];
            return;
        }
        
        if (httpResponse.statusCode != 200) {
            NSError *serverError = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                       code:BugSplatUploadErrorCodeServerError
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status %ld", (long)httpResponse.statusCode]}];
            [self deliverCompletion:^{
                completion(nil, serverError);
            }];
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json[@"url"]) {
            NSError *parseError = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                      code:BugSplatUploadErrorCodeServerError
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid server response"}];
            [self deliverCompletion:^{
                completion(nil, parseError);
            }];
            return;
        }
        
        [self deliverCompletion:^{
            completion(json[@"url"], nil);
        }];
    }];
    
    [self.currentTask resume];
}

#pragma mark - Step 2: Upload to S3

- (void)uploadData:(NSData *)data
   toPresignedURL:(NSString *)presignedURLString
       completion:(void(^)(BOOL success, NSError * _Nullable error))completion
{
    NSURL *presignedURL = [NSURL URLWithString:presignedURLString];
    if (!presignedURL) {
        NSError *error = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                             code:BugSplatUploadErrorCodeInvalidData
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid presigned URL"}];
        completion(NO, error);
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:presignedURL];
    request.HTTPMethod = @"PUT";
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)data.length] forHTTPHeaderField:@"Content-Length"];
    
    self.currentTask = [self.urlSession uploadTaskWithRequest:request fromData:data completionHandler:^(NSData *responseData, NSURLResponse *response, NSError *error) {
        if (error) {
            [self deliverCompletion:^{
                completion(NO, error);
            }];
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSError *uploadError = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                       code:BugSplatUploadErrorCodeServerError
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"S3 upload failed with status %ld", (long)httpResponse.statusCode]}];
            [self deliverCompletion:^{
                completion(NO, uploadError);
            }];
            return;
        }
        
        [self deliverCompletion:^{
            completion(YES, nil);
        }];
    }];
    
    [self.currentTask resume];
}

#pragma mark - Step 3: Commit Upload

- (void)commitUploadWithS3Key:(NSString *)s3Key
                      md5Hash:(NSString *)md5Hash
                     database:(NSString *)database
              applicationName:(NSString *)appName
           applicationVersion:(NSString *)appVersion
                     metadata:(BugSplatCrashMetadata *)metadata
                   completion:(BugSplatUploadCompletion)completion
{
    NSString *urlString = [NSString stringWithFormat:@"https://%@.bugsplat.com/api/commitS3CrashUpload", database];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    
    // Create multipart form data
    NSString *boundary = [[NSUUID UUID] UUIDString];
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    
    NSMutableData *body = [NSMutableData data];
    
    // Required fields - use crash-time values passed as parameters
    [self appendFormField:@"database" value:database boundary:boundary toData:body];
    [self appendFormField:@"appName" value:appName boundary:boundary toData:body];
    [self appendFormField:@"appVersion" value:appVersion boundary:boundary toData:body];
    
    if (metadata.crashTypeId) {
        [self appendFormField:@"crashTypeId" value:metadata.crashTypeId boundary:boundary toData:body];
        if ([metadata.crashTypeId isEqualToString:@"36"]) {
            [self appendFormField:@"crashType" value:@"User.Feedback" boundary:boundary toData:body];
        } else {
#if TARGET_OS_OSX
            [self appendFormField:@"crashType" value:@"macOS" boundary:boundary toData:body];
#else
            [self appendFormField:@"crashType" value:@"iOS" boundary:boundary toData:body];
#endif
        }
    } else {
#if TARGET_OS_OSX
        [self appendFormField:@"crashType" value:@"macOS" boundary:boundary toData:body];
        [self appendFormField:@"crashTypeId" value:@"13" boundary:boundary toData:body];
#else
        [self appendFormField:@"crashType" value:@"iOS" boundary:boundary toData:body];
        [self appendFormField:@"crashTypeId" value:@"26" boundary:boundary toData:body];
#endif
    }
    
    [self appendFormField:@"s3key" value:s3Key boundary:boundary toData:body];
    [self appendFormField:@"md5" value:md5Hash boundary:boundary toData:body];
    
    // Optional metadata fields
    if (metadata.userName.length > 0) {
        [self appendFormField:@"user" value:metadata.userName boundary:boundary toData:body];
    }
    if (metadata.userEmail.length > 0) {
        [self appendFormField:@"email" value:metadata.userEmail boundary:boundary toData:body];
    }
    if (metadata.userDescription.length > 0) {
        [self appendFormField:@"description" value:metadata.userDescription boundary:boundary toData:body];
    }
    if (metadata.applicationLog.length > 0) {
        [self appendFormField:@"appLog" value:metadata.applicationLog boundary:boundary toData:body];
    }
    if (metadata.applicationKey.length > 0) {
        [self appendFormField:@"appKey" value:metadata.applicationKey boundary:boundary toData:body];
    }
    if (metadata.crashTime.length > 0) {
        [self appendFormField:@"crashTime" value:metadata.crashTime boundary:boundary toData:body];
    }
    if (metadata.notes.length > 0) {
        [self appendFormField:@"notes" value:metadata.notes boundary:boundary toData:body];
    }
    
    // Attributes as JSON string
    if (metadata.attributes.count > 0) {
        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:metadata.attributes options:0 error:&jsonError];
        if (jsonData && !jsonError) {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            [self appendFormField:@"attributes" value:jsonString boundary:boundary toData:body];
        }
    }
    
    // Note: Attachments are included in the ZIP file uploaded to S3, not sent here
    
    // End boundary
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    request.HTTPBody = body;
    
    self.currentTask = [self.urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self deliverCompletion:^{
                completion(NO, error, nil, nil);
            }];
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSString *responseBody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSError *commitError = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                       code:BugSplatUploadErrorCodeServerError
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Commit failed with status %ld: %@", (long)httpResponse.statusCode, responseBody ?: @""]}];
            [self deliverCompletion:^{
                completion(NO, commitError, nil, nil);
            }];
            return;
        }
        
        // Parse response to extract infoUrl and the report id (crashId)
        NSString *infoUrl = nil;
        NSNumber *crashId = nil;
        if (data.length > 0) {
            NSError *jsonError = nil;
            NSDictionary *responseJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (!jsonError && [responseJson isKindOfClass:[NSDictionary class]]) {
                id rawInfoUrl = responseJson[@"infoUrl"];
                if ([rawInfoUrl isKindOfClass:[NSString class]]) {
                    infoUrl = rawInfoUrl;
                    NSLog(@"BugSplat: Crash report info URL: %@", infoUrl);
                }
                // crashId is a JSON integer, but tolerate a string-encoded value too.
                id rawCrashId = responseJson[@"crashId"];
                if ([rawCrashId isKindOfClass:[NSNumber class]]) {
                    crashId = rawCrashId;
                } else if ([rawCrashId isKindOfClass:[NSString class]]) {
                    // Only accept a string that is entirely a valid integer —
                    // -longLongValue would otherwise turn garbage into @0.
                    NSString *trimmed = [(NSString *)rawCrashId
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
                    long long parsed = 0;
                    if (trimmed.length > 0 && [scanner scanLongLong:&parsed] && scanner.atEnd) {
                        crashId = @(parsed);
                    }
                }
                if (crashId) {
                    NSLog(@"BugSplat: Crash report id: %@", crashId);
                }
            }
        }

        NSLog(@"BugSplat: Crash report uploaded successfully");
        [self deliverCompletion:^{
            completion(YES, nil, infoUrl, crashId);
        }];
    }];
    
    [self.currentTask resume];
}

#pragma mark - Helpers

- (NSString *)urlEncode:(NSString *)string
{
    return [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
}

- (void)appendFormField:(NSString *)name
                  value:(NSString *)value
               boundary:(NSString *)boundary
                 toData:(NSMutableData *)data
{
    [data appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", name] dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:[[NSString stringWithFormat:@"%@\r\n", value] dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)appendFileField:(NSString *)name
               filename:(NSString *)filename
            contentType:(NSString *)contentType
                   data:(NSData *)fileData
               boundary:(NSString *)boundary
                 toData:(NSMutableData *)data
{
    [data appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", name, filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", contentType ?: @"application/octet-stream"] dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:fileData];
    [data appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
}

@end
