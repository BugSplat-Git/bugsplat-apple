//
//  BSPDemoViews.h
//  BugSplatTest-UIKit-ObjC
//
//  Reusable UIKit views for the demo screen: top-bar pill, database badge,
//  event card, recent-activity row. Mirrors SwiftUI DemoComponents.swift.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Small pill in the top bar showing a colored dot + status text.
@interface BSPStatusPill : UIView
- (instancetype)initWithConnected:(BOOL)connected;
@end

/// Subtle rounded background label used next to the screen title to surface
/// the current BugSplat database name.
@interface BSPDatabaseBadge : UIView
- (instancetype)initWithText:(NSString *)text;
- (void)setText:(NSString *)text;
@end

/// Tappable card used to trigger a demo event. Action target/selector are set
/// in the convenience initializer.
@interface BSPEventCardView : UIControl
- (instancetype)initWithIconName:(NSString *)iconName
                           title:(NSString *)title
                        subtitle:(NSString *)subtitle;
@end

/// One row inside the Recent Activity card: colored dot + bold label + detail
/// + relative-time string aligned to the trailing edge.
@interface BSPRecentActivityRow : UIView
- (instancetype)initWithType:(NSString *)type
                      detail:(NSString *)detail
                   timestamp:(NSTimeInterval)timestamp;
@end

NS_ASSUME_NONNULL_END
