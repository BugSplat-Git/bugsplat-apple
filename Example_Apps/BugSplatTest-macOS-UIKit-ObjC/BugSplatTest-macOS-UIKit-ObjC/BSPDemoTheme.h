//
//  BSPDemoTheme.h
//  BugSplatTest-macOS-UIKit-ObjC
//
//  AppKit color palette matching the iOS samples and the Android refresh.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface BSPDemoTheme : NSObject

@property (class, readonly) NSColor *screenBg;
@property (class, readonly) NSColor *cardBg;
@property (class, readonly) NSColor *cardStroke;
@property (class, readonly) NSColor *textPrimary;
@property (class, readonly) NSColor *textSecondary;
@property (class, readonly) NSColor *textTertiary;
@property (class, readonly) NSColor *badgeBg;
@property (class, readonly) NSColor *pillStroke;
@property (class, readonly) NSColor *connectedDot;
@property (class, readonly) NSColor *link;

@property (class, readonly) NSColor *activityCrash;
@property (class, readonly) NSColor *activityError;
@property (class, readonly) NSColor *activityFeedback;
@property (class, readonly) NSColor *activityHang;

@end

NS_ASSUME_NONNULL_END
