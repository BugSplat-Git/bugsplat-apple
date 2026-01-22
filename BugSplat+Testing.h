//
//  BugSplat+Testing.h
//
//  Private testing interface for BugSplat.
//  This header exposes internal methods for unit testing.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#if TARGET_OS_OSX
  #import <BugSplatMac/BugSplat.h>
#else
  #import <BugSplat/BugSplat.h>
#endif

#import "BugSplatTestSupport.h"
#import "BugSplatUploadService.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Testing interface for BugSplat.
 * Exposes internal methods and allows dependency injection for unit testing.
 */
@interface BugSplat (Testing)

/**
 * Create a new BugSplat instance for testing with injected dependencies.
 * This does NOT affect the shared singleton.
 *
 * @param crashReporter A mock crash reporter.
 * @param crashStorage A mock crash storage.
 * @param userDefaults A mock user defaults.
 * @param bundle A mock bundle.
 * @return A new BugSplat instance for testing.
 */
+ (instancetype)testInstanceWithCrashReporter:(id<BugSplatCrashReporterProtocol>)crashReporter
                                 crashStorage:(id<BugSplatCrashStorageProtocol>)crashStorage
                                 userDefaults:(id<BugSplatUserDefaultsProtocol>)userDefaults
                                       bundle:(id<BugSplatBundleProtocol>)bundle;

/**
 * Internal method to set the upload service (for testing).
 */
- (void)setUploadServiceForTesting:(BugSplatUploadService *)uploadService;

/**
 * Check if start has been invoked.
 */
- (BOOL)isStartInvoked;

/**
 * Check if sending is in progress.
 */
- (BOOL)isSendingInProgress;

/**
 * Get the current crash filename being processed.
 */
- (nullable NSString *)currentCrashFilename;

/**
 * Get the crash reporter (for verification).
 */
- (id<BugSplatCrashReporterProtocol>)crashReporter;

/**
 * Get the crash storage (for verification).
 */
- (id<BugSplatCrashStorageProtocol>)crashStorage;

/**
 * Exposed internal methods for testing.
 */
- (BOOL)shouldSendCrashSilently:(NSDictionary *)metadata;
- (NSString *)resolvedApplicationName;
- (NSString *)resolvedApplicationVersion;

@end

NS_ASSUME_NONNULL_END
