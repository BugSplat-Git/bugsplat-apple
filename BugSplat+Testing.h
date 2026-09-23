//
//  BugSplat+Testing.h
//
//  Private testing interface for BugSplat.
//  This header exposes internal methods for unit testing.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <BugSplat/BugSplat.h>

#import "BugSplatTestSupport.h"
#import "BugSplatUploadService.h"
#import "BugSplatHangTracker.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Class extension to expose private methods for testing.
 * These methods are implemented in the main BugSplat class.
 */
@interface BugSplat () <BugSplatHangTrackerDelegate>

- (BOOL)shouldSendCrashSilently:(NSDictionary *)metadata;
- (NSString *)resolvedApplicationName;
- (NSString *)resolvedApplicationVersion;
- (nullable NSString *)crashesDirectoryPath;
- (void)handleNewCrashFromPLCrashReporter;
- (void)enrichPendingHangReports;
- (void)processPendingCrashReports;
- (void)markAllPendingCrashesAsSubmittedWithUserName:(nullable NSString *)userName
                                           userEmail:(nullable NSString *)userEmail
                                      exceptFilename:(NSString *)crashFilename;

/**
 * Redirects persisted crash and hang reports to `path` instead of the shared directory under
 * Application Support. Pass nil to restore the default.
 *
 * Every BugSplat instance otherwise writes to the same directory. The test schemes set
 * `parallelizable = "YES"`, so XCTest runs test classes in separate worker processes at the
 * same time - and a scan like -enrichPendingHangReports walks every report in that directory,
 * including ones another class planted. Each test that touches the crashes directory points
 * this at its own temporary directory in -setUp and removes it in -tearDown.
 *
 * Declared here rather than in the (Testing) category below: this is the setter of a property
 * synthesized on the main class, and clang warns (-Wincomplete-implementation) about a
 * category that declares a method its own @implementation does not define.
 */
- (void)setCrashesDirectoryPathOverride:(nullable NSString *)path;

/// The basename of the hang report most recently persisted by the hang delegate. Declared here
/// for the same reason as the setter above - it is a synthesized property accessor.
- (nullable NSString *)currentHangFilename;

@end

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
 * Override debugger detection for testing.
 * Pass @YES to simulate debugger attached, @NO to simulate no debugger, nil to use real detection.
 */
- (void)setDebuggerAttachedOverride:(nullable NSNumber *)value;

#pragma mark - Hang Detection Testing

/**
 * Create the internal plumbing (serial queue, launch id) that `-start` would
 * normally set up for hang detection. Lets tests exercise the hang delegate
 * methods without starting the real tracker or enabling the crash reporter.
 */
- (void)setupHangInfrastructureForTesting;

/// Serial queue that hang delegate callbacks dispatch onto; `dispatch_sync` on
/// this queue to wait for pending hang work to drain.
- (nullable dispatch_queue_t)hangQueueForTesting;

@end

NS_ASSUME_NONNULL_END
