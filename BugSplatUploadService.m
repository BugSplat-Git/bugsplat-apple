//
//  BugSplatUploadService.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BugSplatUploadService.h"
#import "BugSplatZipHelper.h"

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
@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, strong, nullable) NSURLSessionTask *currentTask;

@end

@implementation BugSplatUploadService

- (instancetype)initWithDatabase:(NSString *)database
                 applicationName:(NSString *)applicationName
              applicationVersion:(NSString *)applicationVersion
{
    self = [super init];
    if (self) {
        _database = [database copy];
        _applicationName = [applicationName copy];
        _applicationVersion = [applicationVersion copy];
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 60.0;
        config.timeoutIntervalForResource = 300.0;
        _urlSession = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)dealloc
{
    [_urlSession invalidateAndCancel];
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
            completion(NO, error);
            return;
        }
        
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
            completion(NO, error);
            return;
        }
        
        NSString *md5Hash = [BugSplatZipHelper md5HashOfData:zipData];
    
        // Step 1: Get presigned URL
        [self getPresignedURLForSize:zipData.length completion:^(NSString *presignedURL, NSError *error) {
            if (error) {
                completion(NO, error);
                return;
            }
            
            // Step 2: Upload to S3
            [self uploadData:zipData toPresignedURL:presignedURL completion:^(BOOL success, NSError *uploadError) {
                if (!success) {
                    completion(NO, uploadError);
                    return;
                }
                
                // Step 3: Commit the upload
                [self commitUploadWithS3Key:presignedURL
                                    md5Hash:md5Hash
                                   metadata:metadata
                                 completion:completion];
            }];
        }];
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in uploadCrashReport: %@ - %@", exception.name, exception.reason);
        NSError *error = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                             code:BugSplatUploadErrorCodeInvalidData
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Exception: %@", exception.reason]}];
        completion(NO, error);
    }
}

- (void)cancelUpload
{
    [self.currentTask cancel];
    self.currentTask = nil;
}

#pragma mark - Step 1: Get Presigned URL

- (void)getPresignedURLForSize:(NSUInteger)size
                    completion:(void(^)(NSString * _Nullable url, NSError * _Nullable error))completion
{
    NSString *urlString = [NSString stringWithFormat:
        @"https://%@.bugsplat.com/api/getCrashUploadUrl?database=%@&appName=%@&appVersion=%@&crashPostSize=%lu",
        self.database,
        [self urlEncode:self.database],
        [self urlEncode:self.applicationName],
        [self urlEncode:self.applicationVersion],
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
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if (httpResponse.statusCode == 429) {
            NSError *rateLimitError = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                          code:BugSplatUploadErrorCodeRateLimited
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Too many requests"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, rateLimitError);
            });
            return;
        }
        
        if (httpResponse.statusCode != 200) {
            NSError *serverError = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                       code:BugSplatUploadErrorCodeServerError
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status %ld", (long)httpResponse.statusCode]}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, serverError);
            });
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json[@"url"]) {
            NSError *parseError = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                      code:BugSplatUploadErrorCodeServerError
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid server response"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, parseError);
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(json[@"url"], nil);
        });
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
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSError *uploadError = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                       code:BugSplatUploadErrorCodeServerError
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"S3 upload failed with status %ld", (long)httpResponse.statusCode]}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, uploadError);
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, nil);
        });
    }];
    
    [self.currentTask resume];
}

#pragma mark - Step 3: Commit Upload

- (void)commitUploadWithS3Key:(NSString *)s3Key
                      md5Hash:(NSString *)md5Hash
                     metadata:(BugSplatCrashMetadata *)metadata
                   completion:(BugSplatUploadCompletion)completion
{
    NSString *urlString = [NSString stringWithFormat:@"https://%@.bugsplat.com/api/commitS3CrashUpload", self.database];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    
    // Create multipart form data
    NSString *boundary = [[NSUUID UUID] UUIDString];
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    
    NSMutableData *body = [NSMutableData data];
    
    // Required fields
    [self appendFormField:@"database" value:self.database boundary:boundary toData:body];
    [self appendFormField:@"appName" value:self.applicationName boundary:boundary toData:body];
    [self appendFormField:@"appVersion" value:self.applicationVersion boundary:boundary toData:body];
    
#if TARGET_OS_OSX
    [self appendFormField:@"crashType" value:@"macOS" boundary:boundary toData:body];
    [self appendFormField:@"crashTypeId" value:@"13" boundary:boundary toData:body]; // macOS crash type ID
#else
    [self appendFormField:@"crashType" value:@"iOS" boundary:boundary toData:body];
    [self appendFormField:@"crashTypeId" value:@"26" boundary:boundary toData:body]; // iOS crash type ID
#endif
    
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
    if (metadata.crashTime) {
        // Send crash time as Unix timestamp string
        [self appendFormField:@"crashTime" value:[metadata.crashTime stringValue] boundary:boundary toData:body];
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
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSString *responseBody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSError *commitError = [NSError errorWithDomain:BugSplatUploadErrorDomain
                                                       code:BugSplatUploadErrorCodeServerError
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Commit failed with status %ld: %@", (long)httpResponse.statusCode, responseBody ?: @""]}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, commitError);
            });
            return;
        }
        
        NSLog(@"BugSplat: Crash report uploaded successfully");
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, nil);
        });
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
