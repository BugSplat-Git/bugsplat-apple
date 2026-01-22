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
 * Reset the mock state.
 */
- (void)reset;

@end

NS_ASSUME_NONNULL_END
