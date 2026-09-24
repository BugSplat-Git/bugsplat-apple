//
//  AppDelegate.h
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

/// NSUserDefaults key behind the "Share crash reports with the developer" checkbox.
/// Read by -bugSplat:shouldSendCrashReport: to decide whether a pending report is sent.
extern NSString * const BSPShareCrashReportsDefaultsKey;

@interface AppDelegate : NSObject <NSApplicationDelegate>

/// Whether the user has opted in to sharing crash reports. Defaults to YES when the key has
/// never been written, so the sample reports normally out of the box.
///
/// Deliberately does its own absent-key check rather than leaning on -registerDefaults:.
/// The storyboard builds ViewController - and with it the checkbox that reads this - before
/// the app delegate gets -applicationDidFinishLaunching:, so any registration done there is
/// too late, and doing it in +load is too early for NSUserDefaults to be reliable. Checking
/// for nil here has no ordering requirement at all.
+ (BOOL)shareCrashReportsEnabled;

@end

