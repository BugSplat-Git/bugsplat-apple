//
//  BugSplatInit.cpp
//  BugSplatTest-macOS-Tool-CPlusPlus
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#include "BugSplatInit.hpp"

#import <AppKit/AppKit.h> // for NSApplicationDidFinishLaunchingNotification
#import <BugSplatMac/BugSplatMac.h>

@interface MyBugSplatDelegate : NSObject <BugSplatDelegate>
@end


int bugSplatInit(const char * bugSplatDatabase)
{
    @autoreleasepool {
        // Call the C++ function that uses Objective-C
        NSString *databaseName = [NSString stringWithCString:bugSplatDatabase encoding:NSUTF8StringEncoding];
        NSLog(@"bugSplatInit called with database name: %@", databaseName);

        NSBundle *bundle = [NSBundle mainBundle];
        NSLog(@"bugSplatInit mainBundle: %@", bundle == nil ? @"nil" : @"not nil");
        NSString *bundleIdentifier = [bundle bundleIdentifier];
        NSLog(@"bundleIdentifier: %@", bundleIdentifier == nil ? @"nil" : bundleIdentifier);
        NSString *bundleVersion = [[bundle infoDictionary] objectForKey: (NSString *) kCFBundleVersionKey];
        NSLog(@"bundleVersion: %@", bundleVersion == nil ? @"nil" : bundleVersion);
        NSString *bundleMarketingVersion = [[bundle infoDictionary] objectForKey: @"CFBundleShortVersionString"];
        NSLog(@"bundleMarketingVersion: %@", bundleMarketingVersion == nil ? @"nil" : bundleMarketingVersion);


        // Initialize BugSplat
        MyBugSplatDelegate *delegate = [[MyBugSplatDelegate alloc] init];
        [[BugSplat shared] setDelegate:delegate];
        [[BugSplat shared] setAutoSubmitCrashReport:YES];

        // Optionally, add some attributes to your crash reports.
        // Attributes are artibrary key/value pairs that are searchable in the BugSplat dashboard.
        [[BugSplat shared] setValue:@"Value of Plain Attribute" forAttribute:@"PlainAttribute"];
        [[BugSplat shared] setValue:@"Value of not so plain <value> Attribute" forAttribute:@"NotSoPlainAttribute"];
        [[BugSplat shared] setValue:[NSString stringWithFormat:@"Launch Date <![CDATA[%@]]> Value", [NSDate date]] forAttribute:@"CDATAExample"];
        [[BugSplat shared] setValue:[NSString stringWithFormat:@"<!-- 'value is > or < before' --> %@", [NSDate date]] forAttribute:@"CommentExample"];
        [[BugSplat shared] setValue:@"This value will get XML escaping because of 'this' and & and < and >" forAttribute:@"EscapingExample"];

        // Don't forget to call start after you've finished configuring BugSplat
        [[BugSplat shared] setBugSplatDatabase:databaseName];
        [[BugSplat shared] start];

        // Hockey SDK expects a NSApplicationDidFinishLaunchingNotification to be sent before it will process crash reports.
        [[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationDidFinishLaunchingNotification object:nil userInfo:[NSDictionary new]];
    }

    return 0;
}

@implementation MyBugSplatDelegate


- (void)bugSplatWillSendCrashReport:(BugSplat *)bugSplat
{
    NSLog(@"*** bugSplatWillSendCrashReport");
}

- (void)bugSplat:(BugSplat *)bugSplat didFailWithError:(NSError *)error
{
    NSLog(@"*** bugSplat:didFailWithError: %@", error.debugDescription);
}

- (void)bugSplatDidFinishSendingCrashReport:(BugSplat *)bugSplat
{
    NSLog(@"*** bugSplatDidFinishSendingCrashReport");
}

-(void)bugSplatWillShowSubmitCrashReportAlert:(BugSplat *)bugSplat
{
    NSLog(@"*** bugSplatWillShowSubmitCrashReportAlert");
}

-(void)bugSplatWillCancelSendingCrashReport:(BugSplat *)bugSplat
{
    NSLog(@"*** bugSplatWillCancelSendingCrashReport");
}


@end
