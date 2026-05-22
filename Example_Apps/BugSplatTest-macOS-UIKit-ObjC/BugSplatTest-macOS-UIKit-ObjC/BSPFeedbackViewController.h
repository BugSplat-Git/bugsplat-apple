//
//  BSPFeedbackViewController.h
//  BugSplatTest-macOS-UIKit-ObjC
//
//  The redesigned User Feedback experience: a sheet-presented form for
//  composing feedback, and a thank-you confirmation shown in the same sheet
//  after a successful submit. Mirrors the bugsplat-android demo refresh.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Feedback sheet presented from the demo screen via -presentViewControllerAsSheet:.
@interface BSPFeedbackViewController : NSViewController

/// Called after the sheet is dismissed so the presenter can refresh state and
/// clear its feedback-in-progress guard.
@property (nonatomic, copy, nullable) void (^onDismiss)(void);

@end

NS_ASSUME_NONNULL_END
