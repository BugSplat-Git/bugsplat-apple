//
//  BSPFeedbackViewController.h
//  BugSplatTest-UIKit-ObjC
//
//  The redesigned User Feedback experience: a bottom-sheet form for composing
//  feedback, and a thank-you confirmation shown in the same sheet after a
//  successful submit. Mirrors the bugsplat-android demo refresh.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Modal feedback sheet presented from the demo screen.
@interface BSPFeedbackViewController : UIViewController

/// Called after the sheet is dismissed so the presenter can refresh state
/// (a page-sheet dismissal does not trigger the presenter's viewWillAppear).
@property (nonatomic, copy, nullable) void (^onDismiss)(void);

@end

NS_ASSUME_NONNULL_END
