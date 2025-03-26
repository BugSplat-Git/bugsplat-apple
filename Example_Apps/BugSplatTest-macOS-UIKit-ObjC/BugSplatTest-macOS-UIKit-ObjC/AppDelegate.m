//
//  AppDelegate.m
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "AppDelegate.h"
#import "BugSplatMac/BugSplatMac.h"

@interface AppDelegate () <BugSplatDelegate>


@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application

    // Initialize BugSplat
    [[BugSplat shared] setDelegate:self];
    [[BugSplat shared] setAutoSubmitCrashReport:NO];

    // if user enters name and email, store in in NSUserDefaults for use on subsequent crahes
    [[BugSplat shared] setPersistUserDetails:YES];

    // Optionally, add some attributes to your crash reports.
    // Attributes are artibrary key/value pairs that are searchable in the BugSplat dashboard.
    [[BugSplat shared] setValue:@"Value of Plain Attribute" forAttribute:@"PlainAttribute"];
    [[BugSplat shared] setValue:@"Value of not so plain <value> Attribute" forAttribute:@"NotSoPlainAttribute"];
    [[BugSplat shared] setValue:[NSString stringWithFormat:@"Launch Date <![CDATA[%@]]> Value", [NSDate date]] forAttribute:@"CDATAExample"];
    [[BugSplat shared] setValue:[NSString stringWithFormat:@"<!-- 'value is > or < before' --> %@", [NSDate date]] forAttribute:@"CommentExample"];
    [[BugSplat shared] setValue:@"This value will get XML escaping because of 'this' and & and < and >" forAttribute:@"EscapingExample"];
    
    // Don't forget to call start after you've finished configuring BugSplat
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
