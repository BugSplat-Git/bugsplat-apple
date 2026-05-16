//
//  BSPActivityLog.m
//  BugSplatTest-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BSPActivityLog.h"

NSString * const BSPActivityTypeCrash    = @"crash";
NSString * const BSPActivityTypeError    = @"error";
NSString * const BSPActivityTypeFeedback = @"feedback";
NSString * const BSPActivityTypeHang     = @"hang";

NSString * const BSPActivityEntryKeyType      = @"type";
NSString * const BSPActivityEntryKeyDetail    = @"detail";
NSString * const BSPActivityEntryKeyTimestamp = @"ts";

static NSString * const kBSPActivityDefaultsKey = @"bugsplat.example.activity.entries";
static const NSUInteger kBSPActivityMaxEntries = 10;

@implementation BSPActivityLog

+ (void)record:(NSString *)type detail:(NSString *)detail {
    NSMutableArray<NSDictionary *> *entries = [[self all] mutableCopy];
    NSDictionary *entry = @{
        BSPActivityEntryKeyType: type ?: @"",
        BSPActivityEntryKeyDetail: detail ?: @"",
        BSPActivityEntryKeyTimestamp: @([[NSDate date] timeIntervalSince1970])
    };
    [entries insertObject:entry atIndex:0];
    if (entries.count > kBSPActivityMaxEntries) {
        [entries removeObjectsInRange:NSMakeRange(kBSPActivityMaxEntries,
                                                  entries.count - kBSPActivityMaxEntries)];
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:entries options:0 error:&error];
    if (!data) return;
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:kBSPActivityDefaultsKey];
    if ([type isEqualToString:BSPActivityTypeCrash]) {
        // Best-effort sync flush before the impending crash. synchronize() is
        // deprecated but still the closest analog to Android's commit().
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

+ (NSArray<NSDictionary *> *)all {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:kBSPActivityDefaultsKey];
    if (!data) return @[];
    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![parsed isKindOfClass:[NSArray class]]) return @[];
    return (NSArray<NSDictionary *> *)parsed;
}

+ (void)clear {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kBSPActivityDefaultsKey];
}

+ (NSString *)relativeTimeStringFromSeconds:(NSTimeInterval)seconds {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval elapsed = MAX(0.0, now - seconds);
    NSInteger minutes = (NSInteger)(elapsed / 60.0);
    if (minutes < 1) return @"just now";
    if (minutes < 60) return [NSString stringWithFormat:@"%ldm ago", (long)minutes];
    NSInteger hours = minutes / 60;
    if (hours < 24) return [NSString stringWithFormat:@"%ldh ago", (long)hours];
    return [NSString stringWithFormat:@"%ldd ago", (long)(hours / 24)];
}

@end
