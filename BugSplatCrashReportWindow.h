//
//  BugSplatCrashReportWindow.h
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#if TARGET_OS_OSX

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * User action from the crash report dialog.
 */
typedef NS_ENUM(NSUInteger, BugSplatUserAction) {
    BugSplatUserActionSend,
    BugSplatUserActionCancel
};

/**
 * Completion handler for crash report dialog.
 *
 * @param action The action the user took (send or cancel).
 * @param userName The name entered by the user (may be nil).
 * @param userEmail The email entered by the user (may be nil).
 * @param comments The comments entered by the user (may be nil).
 */
typedef void(^BugSplatCrashReportCompletion)(BugSplatUserAction action,
                                              NSString * _Nullable userName,
                                              NSString * _Nullable userEmail,
                                              NSString * _Nullable comments);

/**
 * Window controller for the crash report dialog.
 * Displays a user-friendly interface for submitting crash reports.
 */
@interface BugSplatCrashReportWindow : NSWindowController

/**
 * The application name to display in the dialog.
 */
@property (nonatomic, copy) NSString *applicationName;

/**
 * Custom banner image to display at the top of the dialog.
 * If nil, a default BugSplat logo will be used if available.
 */
@property (nonatomic, strong, nullable) NSImage *bannerImage;

/**
 * The crash report text to show in the details view.
 */
@property (nonatomic, copy, nullable) NSString *crashReportText;

/**
 * Whether to show the name and email fields.
 * Default is YES.
 */
@property (nonatomic, assign) BOOL askUserDetails;

/**
 * Pre-filled user name (from persisted data).
 */
@property (nonatomic, copy, nullable) NSString *prefillUserName;

/**
 * Pre-filled user email (from persisted data).
 */
@property (nonatomic, copy, nullable) NSString *prefillUserEmail;

/**
 * Shows the crash report dialog and calls completion when user makes a choice.
 *
 * @param completion Called when user clicks Send or Cancel.
 */
- (void)showWithCompletion:(BugSplatCrashReportCompletion)completion;

/**
 * Shows the dialog modally, blocking until user makes a choice.
 *
 * @param completion Called when user clicks Send or Cancel.
 */
- (void)showModalWithCompletion:(BugSplatCrashReportCompletion)completion;

@end

NS_ASSUME_NONNULL_END

#endif
