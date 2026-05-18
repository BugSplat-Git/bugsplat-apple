//
//  BSPDemoTheme.m
//  BugSplatTest-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BSPDemoTheme.h"

@implementation BSPDemoTheme

+ (UIColor *)colorWithHex:(uint32_t)hex {
    CGFloat r = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat g = ((hex >>  8) & 0xFF) / 255.0;
    CGFloat b = ( hex        & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

+ (UIColor *)screenBg      { return [self colorWithHex:0xFAF8F2]; }
+ (UIColor *)cardBg        { return [self colorWithHex:0xFFFFFF]; }
+ (UIColor *)cardStroke    { return [self colorWithHex:0xECEAE2]; }
+ (UIColor *)textPrimary   { return [self colorWithHex:0x0E1116]; }
// Both secondary and tertiary clear WCAG AA (≥4.5:1) against the card and
// screen backgrounds. Tertiary used to be a lighter gray (#9CA3AF, ~2.5:1)
// but small section headers and footers became hard to read.
+ (UIColor *)textSecondary { return [self colorWithHex:0x4B5563]; }
+ (UIColor *)textTertiary  { return [self colorWithHex:0x6B7280]; }
+ (UIColor *)badgeBg       { return [self colorWithHex:0xF1EFE8]; }
+ (UIColor *)pillStroke    { return [self colorWithHex:0xE4E2DA]; }
+ (UIColor *)connectedDot  { return [self colorWithHex:0x22C55E]; }
+ (UIColor *)link          { return [self colorWithHex:0x1F73E8]; }

+ (UIColor *)activityCrash    { return [self colorWithHex:0x1F73E8]; }
+ (UIColor *)activityError    { return [self colorWithHex:0xE5B142]; }
+ (UIColor *)activityFeedback { return [self colorWithHex:0x22C55E]; }
+ (UIColor *)activityHang     { return [self colorWithHex:0xE5B142]; }

@end
