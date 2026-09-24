//
//  AppDelegate.h
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

/// NSUserDefaults key behind the "Share crash reports with the developer" checkbox.
/// Read by -bugSplat:shouldSendCrashReport: to decide whether a pending report is sent.
/// Registered as YES, so the sample reports normally until you turn it off.
extern NSString * const BSPShareCrashReportsDefaultsKey;

@interface AppDelegate : NSObject <NSApplicationDelegate>


@end

