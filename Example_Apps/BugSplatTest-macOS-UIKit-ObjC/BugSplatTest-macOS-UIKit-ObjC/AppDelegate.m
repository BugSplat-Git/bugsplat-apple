//
//  AppDelegate.m
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Created by David Ferrero on 4/26/24.
//

#import "AppDelegate.h"
#import "BugSplatMac/BugSplatMac.h"

@interface AppDelegate () <BugSplatDelegate>


@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application

    // initialize BugSplat
    [[BugSplat shared] setDelegate:self];
//    [[BugSplat shared] setAutoSubmitCrashReport:NO];
    [[BugSplat shared] start];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

#pragma mark - BugSplatDelegate

- (void)bugSplatWillSendCrashReport:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillSendCrashReport called");
}

- (void)bugSplatWillSendCrashReportsAlways:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillSendCrashReportsAlways called");
}

- (void)bugSplatDidFinishSendingCrashReport:(BugSplat *)bugSplat {
    NSLog(@"bugSplatDidFinishSendingCrashReport called");
}

- (void)bugSplatWillCancelSendingCrashReport:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillCancelSendingCrashReport called");
}

- (void)bugSplatWillShowSubmitCrashReportAlert:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillShowSubmitCrashReportAlert called");
}

- (void)bugSplat:(BugSplat *)bugSplat didFailWithError:(NSError *)error {
    NSLog(@"bugSplat:didFailWithError: %@", [error localizedDescription]);
}

@end
