//
//  BugSplatUploadService.h
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BugSplatAttachment.h"
#import "BugSplatTestSupport.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Metadata to include with crash report upload.
 * All values represent crash-time context - they may differ from current app values
 * if the app was updated between when the crash occurred and when it's uploaded.
 */
@interface BugSplatCrashMetadata : NSObject

/**
 * Crash-time context - these values are captured when the crash occurs and may
 * differ from current app values if the app was updated before the crash is uploaded.
 */
@property (nonatomic, copy, nullable) NSString *database;
@property (nonatomic, copy, nullable) NSString *applicationName;
@property (nonatomic, copy, nullable) NSString *applicationVersion;

@property (nonatomic, copy, nullable) NSString *userName;
@property (nonatomic, copy, nullable) NSString *userEmail;
@property (nonatomic, copy, nullable) NSString *userDescription;
@property (nonatomic, copy, nullable) NSString *applicationLog;
@property (nonatomic, copy, nullable) NSString *applicationKey;
@property (nonatomic, copy, nullable) NSString *notes;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *attributes;

/**
 * The time the crash occurred (ISO 8601 formatted string).
 * This may differ from upload time if the crash couldn't be sent immediately.
 */
@property (nonatomic, copy, nullable) NSString *crashTime;

/**
 * The crash type ID to use for this upload.
 * When set, overrides the default platform-specific crash type ID.
 * Use @"36" for user feedback submissions.
 */
@property (nonatomic, copy, nullable) NSString *crashTypeId;

@end

/**
 * Completion handler for upload operations.
 *
 * @param success YES if the upload was successful.
 * @param error Error object if the upload failed, nil otherwise.
 * @param infoUrl URL to the crash report details page (only provided on success).
 */
typedef void(^BugSplatUploadCompletion)(BOOL success, NSError * _Nullable error, NSString * _Nullable infoUrl);

/**
 * Service for uploading crash reports to BugSplat servers.
 * Implements the S3 presigned URL upload flow.
 */
@interface BugSplatUploadService : NSObject

/**
 * Creates a new upload service instance.
 *
 * @param database The BugSplat database name.
 * @param applicationName The application name.
 * @param applicationVersion The application version string.
 * @return A configured upload service instance.
 */
- (instancetype)initWithDatabase:(NSString *)database
                 applicationName:(NSString *)applicationName
              applicationVersion:(NSString *)applicationVersion;

/**
 * Creates a new upload service instance with a custom URL session (for testing).
 *
 * @param database The BugSplat database name.
 * @param applicationName The application name.
 * @param applicationVersion The application version string.
 * @param urlSession A custom URL session conforming to BugSplatURLSessionProtocol.
 * @return A configured upload service instance.
 */
- (instancetype)initWithDatabase:(NSString *)database
                 applicationName:(NSString *)applicationName
              applicationVersion:(NSString *)applicationVersion
                      urlSession:(id<BugSplatURLSessionProtocol>)urlSession;

/**
 * Uploads a crash report to BugSplat.
 *
 * @param crashData The crash report data (will be zipped before upload).
 * @param crashFilename The filename to use for the crash report inside the zip.
 * @param attachments Optional array of attachments to include.
 * @param metadata Optional metadata (user info, description, etc).
 * @param completion Called when upload completes or fails.
 */
- (void)uploadCrashReport:(NSData *)crashData
            crashFilename:(NSString *)crashFilename
              attachments:(nullable NSArray<BugSplatAttachment *> *)attachments
                 metadata:(nullable BugSplatCrashMetadata *)metadata
               completion:(BugSplatUploadCompletion)completion;

/**
 * Uploads user feedback to BugSplat.
 *
 * Creates a feedback.json file containing the title and description,
 * zips it along with any attachments, and uploads using the standard
 * 3-step presigned URL flow with crashTypeId=36 (User.Feedback).
 *
 * @param title The feedback title.
 * @param description Optional feedback description.
 * @param attachments Optional array of file attachments to include.
 * @param metadata Metadata (database, app info, user info, etc).
 * @param completion Called when upload completes or fails.
 */
- (void)uploadFeedback:(NSString *)title
           description:(nullable NSString *)description
           attachments:(nullable NSArray<BugSplatAttachment *> *)attachments
              metadata:(BugSplatCrashMetadata *)metadata
            completion:(void (^)(NSError * _Nullable error))completion;

/**
 * Cancels any in-progress upload.
 */
- (void)cancelUpload;

@end

NS_ASSUME_NONNULL_END
