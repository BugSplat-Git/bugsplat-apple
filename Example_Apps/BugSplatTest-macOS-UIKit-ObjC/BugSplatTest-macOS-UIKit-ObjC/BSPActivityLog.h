//
//  BSPActivityLog.h
//  BugSplatTest-UIKit-ObjC
//
//  Local persistence of user-triggered demo events. Mirrors the SwiftUI and
//  Android samples so the demo UIs stay consistent across platforms.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// String constants for the four activity types stored in the entry dictionaries.
extern NSString * const BSPActivityTypeCrash;
extern NSString * const BSPActivityTypeError;
extern NSString * const BSPActivityTypeFeedback;
extern NSString * const BSPActivityTypeHang;

/// Keys used inside each entry dictionary returned by `+all`.
extern NSString * const BSPActivityEntryKeyType;
extern NSString * const BSPActivityEntryKeyDetail;
extern NSString * const BSPActivityEntryKeyTimestamp;

@interface BSPActivityLog : NSObject

/// Insert a new entry at the head of the list (newest first) and persist.
/// Caps the list at 10 entries. For crash entries, calls `synchronize` so
/// the record survives the impending process death.
+ (void)record:(NSString *)type detail:(NSString *)detail;

/// All entries, newest first. Each dictionary contains the keys defined above.
+ (NSArray<NSDictionary *> *)all;

/// Remove all entries.
+ (void)clear;

/// Relative-time string for a timestamp ("just now", "Xm ago", "Xh ago", "Xd ago").
+ (NSString *)relativeTimeStringFromSeconds:(NSTimeInterval)seconds;

@end

NS_ASSUME_NONNULL_END
