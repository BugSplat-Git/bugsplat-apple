//
//  BSPDemoViews.h
//  BugSplatTest-macOS-UIKit-ObjC
//
//  AppKit reusable views: status pill, database badge, event card (with optional
//  keyboard shortcut chip), recent-activity row, and a rounded card container.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Rounded white card with a 1pt cardStroke border. Used as the visual container
/// for event cards and the recent-activity card.
@interface BSPRoundedCardView : NSView
@property (nonatomic, assign) CGFloat cornerRadius;
@end


/// Small capsule with a green dot + label ("Connected" / "Offline").
@interface BSPStatusPill : NSView
- (instancetype)initWithConnected:(BOOL)connected;
@end


/// Small rounded badge label - used in the title row to surface the configured
/// BugSplat database name.
@interface BSPDatabaseBadge : NSView
- (instancetype)initWithText:(NSString *)text;
@end


/// Tiny ⌘N chip shown in the top-right corner of each event card.
@interface BSPShortcutChip : NSView
- (instancetype)initWithText:(NSString *)text;
@end


/// Clickable card with splat icon + title + subtitle and (optionally) a shortcut
/// chip. Fires `target/action` on mouseUp inside.
@interface BSPEventCardView : NSControl
- (instancetype)initWithIconNamed:(NSString *)imageName
                            title:(NSString *)title
                         subtitle:(NSString *)subtitle
                         shortcut:(nullable NSString *)shortcut;
@end


/// One row in the Recent Activity list.
@interface BSPRecentActivityRow : NSView
- (instancetype)initWithType:(NSString *)type
                       detail:(NSString *)detail
                  relativeTime:(NSString *)relativeTime;
@end

NS_ASSUME_NONNULL_END
