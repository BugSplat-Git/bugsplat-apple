//
//  BugSplatTestCrashDirectory.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BugSplatTestCrashDirectory.h"

NSString *BugSplatTestsMakeIsolatedCrashesDirectory(void)
{
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"BugSplatTests-%@", [NSUUID UUID].UUIDString]];
}
