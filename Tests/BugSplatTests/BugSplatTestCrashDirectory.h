//
//  BugSplatTestCrashDirectory.h
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Returns a crashes directory path unique to the caller.
 *
 * Every BugSplat instance otherwise persists reports to one shared directory under
 * Application Support. The test schemes set `parallelizable = "YES"`, so XCTest runs test
 * classes in separate worker processes at the same time - and a scan like
 * -enrichPendingHangReports walks every report in that directory, including ones another
 * class planted, which made those tests fail intermittently.
 *
 * Pass the result to -setCrashesDirectoryPathOverride: (BugSplat+Testing.h) in -setUp, and
 * remove the directory in -tearDown. The directory is not created here; BugSplat creates it
 * on first use.
 */
FOUNDATION_EXPORT NSString *BugSplatTestsMakeIsolatedCrashesDirectory(void);

NS_ASSUME_NONNULL_END
