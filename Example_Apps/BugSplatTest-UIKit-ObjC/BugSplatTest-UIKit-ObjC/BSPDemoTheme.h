//
//  BSPDemoTheme.h
//  BugSplatTest-UIKit-ObjC
//
//  Palette mirrors the SwiftUI sample's DemoTheme.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BSPDemoTheme : NSObject

+ (UIColor *)screenBg;
+ (UIColor *)cardBg;
+ (UIColor *)cardStroke;
+ (UIColor *)textPrimary;
+ (UIColor *)textSecondary;
+ (UIColor *)textTertiary;
+ (UIColor *)badgeBg;
+ (UIColor *)pillStroke;
+ (UIColor *)connectedDot;
+ (UIColor *)link;

+ (UIColor *)activityCrash;
+ (UIColor *)activityError;
+ (UIColor *)activityFeedback;
+ (UIColor *)activityHang;

/// Build a UIColor from a packed 0xRRGGBB integer.
+ (UIColor *)colorWithHex:(uint32_t)hex;

@end

NS_ASSUME_NONNULL_END
