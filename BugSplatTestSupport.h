//
//  BugSplatTestSupport.h
//
//  Protocols and utilities for testing BugSplat components.
//  These protocols allow dependency injection for unit testing.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - URL Session Protocol

/**
 * Protocol for URL session operations.
 * NSURLSession already conforms to this implicitly, but having an explicit protocol
 * allows for easy mocking in tests.
 */
@protocol BugSplatURLSessionProtocol <NSObject>

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;

- (void)invalidateAndCancel;

@end

// NSURLSession implicitly conforms to BugSplatURLSessionProtocol
// This category makes it explicit for documentation purposes


#pragma mark - Crash Reporter Protocol

/**
 * Protocol for crash reporter operations.
 * Allows mocking of PLCrashReporter for unit testing.
 */
@protocol BugSplatCrashReporterProtocol <NSObject>

/**
 * Check if there is a pending crash report from the previous session.
 */
- (BOOL)hasPendingCrashReport;

/**
 * Load the pending crash report data.
 */
- (nullable NSData *)loadPendingCrashReportDataAndReturnError:(NSError **)outError;

/**
 * Purge (delete) the pending crash report.
 */
- (void)purgePendingCrashReport;

/**
 * Enable the crash reporter.
 */
- (BOOL)enableCrashReporterAndReturnError:(NSError **)outError;

/**
 * Custom data to embed in crash reports.
 */
@property (nonatomic, strong, nullable) NSData *customData;

@end


#pragma mark - Crash Storage Protocol

/**
 * Protocol for crash report file storage operations.
 * Allows mocking of file system operations for unit testing.
 */
@protocol BugSplatCrashStorageProtocol <NSObject>

/**
 * Returns the path to the crashes directory, creating it if necessary.
 */
- (nullable NSString *)crashesDirectoryPath;

/**
 * Get a list of pending crash filenames (without extension), sorted oldest first.
 */
- (NSArray<NSString *> *)getPendingCrashFiles;

/**
 * Persist crash report data to disk.
 *
 * @param data The crash report data.
 * @param filename The base filename (without extension).
 * @return YES if successful, NO otherwise.
 */
- (BOOL)persistCrashData:(NSData *)data withFilename:(NSString *)filename;

/**
 * Load crash report data from disk.
 *
 * @param filename The base filename (without extension).
 * @return The crash data, or nil if not found.
 */
- (nullable NSData *)loadCrashDataWithFilename:(NSString *)filename;

/**
 * Persist metadata for a crash report.
 *
 * @param metadata The metadata dictionary.
 * @param filename The base filename (without extension).
 * @return YES if successful, NO otherwise.
 */
- (BOOL)persistMetadata:(NSDictionary *)metadata forFilename:(NSString *)filename;

/**
 * Load metadata for a crash report.
 *
 * @param filename The base filename (without extension).
 * @return The metadata dictionary, or nil if not found.
 */
- (nullable NSDictionary *)loadMetadataForFilename:(NSString *)filename;

/**
 * Persist an array of attachment data for a crash.
 *
 * @param attachmentsData Array of archived attachment data.
 * @param filename The base crash filename.
 */
- (void)persistAttachmentsData:(NSArray<NSData *> *)attachmentsData forFilename:(NSString *)filename;

/**
 * Load persisted attachments for a crash.
 *
 * @param filename The base crash filename.
 * @return Array of archived attachment data.
 */
- (NSArray<NSData *> *)loadAttachmentsDataForFilename:(NSString *)filename;

/**
 * Cleanup all files associated with a crash report.
 *
 * @param filename The base filename (without extension).
 */
- (void)cleanupCrashReportWithFilename:(NSString *)filename;

/**
 * Cleanup all pending crash reports.
 */
- (void)cleanupAllPendingCrashReports;

@end


#pragma mark - Bundle Protocol

/**
 * Protocol for accessing bundle information.
 * Allows mocking of NSBundle for unit testing.
 */
@protocol BugSplatBundleProtocol <NSObject>

- (nullable id)objectForInfoDictionaryKey:(NSString *)key;

@end

// NSBundle implicitly conforms to BugSplatBundleProtocol


#pragma mark - User Defaults Protocol

/**
 * Protocol for user defaults operations.
 * Allows mocking of NSUserDefaults for unit testing.
 */
@protocol BugSplatUserDefaultsProtocol <NSObject>

- (nullable NSString *)stringForKey:(NSString *)defaultName;
- (BOOL)boolForKey:(NSString *)defaultName;
- (void)setObject:(nullable id)value forKey:(NSString *)defaultName;
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName;

@end

// NSUserDefaults implicitly conforms to BugSplatUserDefaultsProtocol

NS_ASSUME_NONNULL_END
