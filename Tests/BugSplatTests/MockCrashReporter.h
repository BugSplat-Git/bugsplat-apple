//
//  MockCrashReporter.h
//  BugSplatTests
//
//  Mock implementation of crash reporter for testing.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BugSplatTestSupport.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Mock crash reporter for testing.
 */
@interface MockCrashReporter : NSObject <BugSplatCrashReporterProtocol>

/**
 * Configure whether there's a pending crash report.
 */
@property (nonatomic, assign) BOOL hasPendingReport;

/**
 * The data to return when loading the pending crash report.
 */
@property (nonatomic, strong, nullable) NSData *pendingCrashReportData;

/**
 * Error to return when loading the pending crash report.
 */
@property (nonatomic, strong, nullable) NSError *loadError;

/**
 * Error to return when enabling the crash reporter.
 */
@property (nonatomic, strong, nullable) NSError *enableError;

/**
 * Track if crash reporter was enabled.
 */
@property (nonatomic, readonly) BOOL wasEnabled;

/**
 * Track if pending report was purged.
 */
@property (nonatomic, readonly) BOOL wasPurged;

/**
 * Custom data set on the crash reporter.
 */
@property (nonatomic, strong, nullable) NSData *customData;

/**
 * The data to return from -generateLiveReportWithException:error:.
 *
 * Non-fatal reporting parses this with PLCrashReport, so tests that expect the happy path
 * must supply data a real reporter produced - see +liveReportDataWithException: below.
 */
@property (nonatomic, strong, nullable) NSData *liveReportData;

/**
 * Error to return from -generateLiveReportWithException:error:. When set, nil data is returned.
 */
@property (nonatomic, strong, nullable) NSError *liveReportError;

/**
 * Number of times -generateLiveReportWithException:error: has been called.
 */
@property (nonatomic, readonly) NSUInteger liveReportCallCount;

/**
 * The exception passed to the most recent -generateLiveReportWithException:error: call.
 */
@property (nonatomic, strong, readonly, nullable) NSException *lastLiveReportException;

/**
 * Produces real PLCrashReporter live-report data for the given exception, for tests that need
 * -generateLiveReportWithException:error: to return something BugSplat can actually parse.
 *
 * @return Report data, or nil if the underlying reporter could not produce one.
 */
+ (nullable NSData *)liveReportDataWithException:(nullable NSException *)exception;

/**
 * Reset the mock state.
 */
- (void)reset;

@end

NS_ASSUME_NONNULL_END
