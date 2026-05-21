//
//  BSPDemoTheme.m
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BSPDemoTheme.h"

static NSColor *Hex(uint32_t rgb) {
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((rgb >>  8) & 0xFF) / 255.0;
    CGFloat b = ( rgb        & 0xFF) / 255.0;
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
}

@implementation BSPDemoTheme

+ (NSColor *)screenBg         { return Hex(0xFAF8F2); }
+ (NSColor *)cardBg           { return Hex(0xFFFFFF); }
+ (NSColor *)cardStroke       { return Hex(0xECEAE2); }
+ (NSColor *)textPrimary      { return Hex(0x0E1116); }
// Both secondary and tertiary clear WCAG AA (≥4.5:1) against the card and
// screen backgrounds. Tertiary used to be a lighter gray (#9CA3AF, ~2.5:1)
// but small section headers and footers became hard to read.
+ (NSColor *)textSecondary    { return Hex(0x4B5563); }
+ (NSColor *)textTertiary     { return Hex(0x6B7280); }
+ (NSColor *)badgeBg          { return Hex(0xF1EFE8); }
+ (NSColor *)pillStroke       { return Hex(0xE4E2DA); }
+ (NSColor *)connectedDot     { return Hex(0x22C55E); }
+ (NSColor *)link             { return Hex(0x1F73E8); }

+ (NSColor *)activityCrash    { return Hex(0x1F73E8); }
+ (NSColor *)activityError    { return Hex(0xE5B142); }
+ (NSColor *)activityFeedback { return Hex(0x22C55E); }
+ (NSColor *)activityHang     { return Hex(0xE5B142); }

+ (NSColor *)feedbackAccent   { return Hex(0x4E9D78); }
+ (NSColor *)footerBg         { return Hex(0xF4F2EA); }
+ (NSColor *)asterisk         { return Hex(0xDC2626); }

@end
