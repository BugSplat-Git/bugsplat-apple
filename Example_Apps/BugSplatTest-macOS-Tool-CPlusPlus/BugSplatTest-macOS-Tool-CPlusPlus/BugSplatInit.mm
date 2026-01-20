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

/// URL for the sample log file that will be attached to crash reports
@property (nonatomic, strong) NSURL *logFileURL;

/// Creates a sample log file for attachment demonstration
- (void)createSampleLogFile;

@end


// Call the C++ function that uses Objective-C
int bugSplatInit(const char * bugSplatDatabase)
{
    @autoreleasepool {
/*
        // BugSplat expects bundleIdentifier, bundleVersion and optionally bundleMarketingVersion to be set within the Info.plist
        // Uncomment this section to show the values that BugSplat is seeing and ensure they are set
        NSBundle *bundle = [NSBundle mainBundle];
        NSLog(@"bugSplatInit mainBundle: %@", bundle == nil ? @"nil" : @"not nil");
        NSString *bundleIdentifier = [bundle bundleIdentifier];
        NSLog(@"bundleIdentifier: %@", bundleIdentifier == nil ? @"nil" : bundleIdentifier);
        NSString *bundleVersion = [[bundle infoDictionary] objectForKey: (NSString *) kCFBundleVersionKey];
        NSLog(@"bundleVersion: %@", bundleVersion == nil ? @"nil" : bundleVersion);
        NSString *bundleMarketingVersion = [[bundle infoDictionary] objectForKey: @"CFBundleShortVersionString"];
        NSLog(@"bundleMarketingVersion: %@", bundleMarketingVersion == nil ? @"nil" : bundleMarketingVersion);
*/

        // Initialize BugSplat
        MyBugSplatDelegate *delegate = [[MyBugSplatDelegate alloc] init];
        
        // Create a sample log file for attachment demonstration
        [delegate createSampleLogFile];

        // Set a BugSplatDelegate
        [[BugSplat shared] setDelegate:delegate];

        // Command Line Tools do not have a GUI. setAutoSubmitCrashReport: YES
        [[BugSplat shared] setAutoSubmitCrashReport:YES];

/*
        // Optionally, add some attributes to your crash reports.
        // Attributes are artibrary key/value pairs that are searchable in the BugSplat dashboard.
        [[BugSplat shared] setValue:@"Value of Plain Attribute" forAttribute:@"PlainAttribute"];
        [[BugSplat shared] setValue:@"Value of not so plain <value> Attribute" forAttribute:@"NotSoPlainAttribute"];
        [[BugSplat shared] setValue:[NSString stringWithFormat:@"Launch Date <![CDATA[%@]]> Value", [NSDate date]] forAttribute:@"CDATAExample"];
        [[BugSplat shared] setValue:[NSString stringWithFormat:@"<!-- 'value is > or < before' --> %@", [NSDate date]] forAttribute:@"CommentExample"];
        [[BugSplat shared] setValue:@"This value will get XML escaping because of 'this' and & and < and >" forAttribute:@"EscapingExample"];
*/
        NSString *databaseName = [NSString stringWithCString:bugSplatDatabase encoding:NSUTF8StringEncoding];
        NSLog(@"bugSplatInit called with database name: %@", databaseName);

        // Set the BugSplatDatabase name before calling start
        [[BugSplat shared] setBugSplatDatabase:databaseName];

        // Don't forget to call start after you've finished configuring BugSplat
        [[BugSplat shared] start];

        // BugSplat expects a NSApplicationDidFinishLaunchingNotification to be sent before it will process crash reports.
        // In a command line tool without a normal app launch, send the notification manually. This must be sent after [[BugSplat shared] start]
        [[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationDidFinishLaunchingNotification object:nil userInfo:[NSDictionary new]];
    }

    return 0;
}

int bugSplatSetAttributeValue(std::string attribute, std::string value)
{
    @autoreleasepool {
        NSString *attributeString = @(attribute.c_str());
        NSString *valueString = @(value.c_str());
        NSLog(@"bugSplatSetAttributeValue(%@, %@)", attributeString, valueString);

        // Attributes can be set any time and can contain dynamic values
        // Attributes set in this app session will only appear if the app session in which they are set terminates with an app crash
        [[BugSplat shared] setValue:valueString forAttribute:attributeString];
    }

    return 0;
}

void mainObjCRunLoop() {
    @autoreleasepool {
        // Objective-C often needs an NSRunLoop
        // BugSplat needs a NSRunLoop to process events
        // give run loop 3 seconds to process any events
        NSLog(@"*** mainObjCRunLoop giving NSRunLoop time to run...");

        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
    }
}


@implementation MyBugSplatDelegate

#pragma mark - Sample Log File

/// Creates a sample log file in the temp directory for attachment demonstration
- (void)createSampleLogFile {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.logFileURL = [tempURL URLByAppendingPathComponent:@"sample_log.txt"];
    
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    NSDate *now = [NSDate date];
    
    NSString *logContent = [NSString stringWithFormat:
        @"=====================================\n"
        @"BugSplat Sample Log File\n"
        @"=====================================\n"
        @"App Launch: %@\n"
        @"Host Name: %@\n"
        @"OS Version: %@\n"
        @"Process Name: %@\n"
        @"Process ID: %d\n"
        @"\n"
        @"This is a sample log file demonstrating how to attach\n"
        @"files to BugSplat crash reports from a command line tool.\n"
        @"\n"
        @"You can use this pattern to attach:\n"
        @"- Application logs\n"
        @"- Configuration files\n"
        @"- Diagnostic data\n"
        @"- Any other relevant debugging information\n"
        @"\n"
        @"Log entries:\n"
        @"[%@] INFO: Command line tool started\n"
        @"[%@] DEBUG: BugSplat initialized\n"
        @"[%@] INFO: Sample log file created for attachment demo\n"
        @"=====================================\n",
        now, processInfo.hostName, processInfo.operatingSystemVersionString,
        processInfo.processName, processInfo.processIdentifier, now, now, now];
    
    NSError *error = nil;
    BOOL success = [logContent writeToURL:self.logFileURL
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&error];
    
    if (success) {
        NSLog(@"Sample log file created at: %@", self.logFileURL.path);
    } else {
        NSLog(@"Failed to create sample log file: %@", error.localizedDescription);
        self.logFileURL = nil;
    }
}

#pragma mark - BugSplatDelegate

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

/// Returns an array of file attachments to include with the crash report
/// This demonstrates how to attach log files or other data to crash reports
/// Note: macOS supports multiple attachments, unlike iOS which only supports one
- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat {
    if (!self.logFileURL) {
        NSLog(@"Could not read log file for attachment - no URL");
        return @[];
    }
    
    NSError *error = nil;
    NSData *logData = [NSData dataWithContentsOfURL:self.logFileURL options:0 error:&error];
    
    if (!logData) {
        NSLog(@"Could not read log file for attachment: %@", error.localizedDescription);
        return @[];
    }
    
    NSLog(@"Attaching log file to crash report: %@", self.logFileURL.lastPathComponent);
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:@"sample_log.txt"
                                                                   attachmentData:logData
                                                                      contentType:@"text/plain"];
    return @[attachment];
}

@end
