//
//  AppDelegate.m
//  BugSplatTest-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "AppDelegate.h"
#import "BugSplat/BugSplat.h"

@interface AppDelegate () <BugSplatDelegate>

/// URL for the sample log file that will be attached to crash reports
@property (nonatomic, strong) NSURL *logFileURL;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    
    // Create a sample log file for attachment demonstration
    [self createSampleLogFile];

    // Initialize BugSplat
    [[BugSplat shared] setDelegate:self];
    [[BugSplat shared] setAutoSubmitCrashReport:NO];

    // Optionally, add some attributes to your crash reports.
    // Attributes are artibrary key/value pairs that are searchable in the BugSplat dashboard.
    [[BugSplat shared] setValue:@"Value of Plain Attribute" forAttribute:@"PlainAttribute"];
    [[BugSplat shared] setValue:@"Value of not so plain <value> Attribute" forAttribute:@"NotSoPlainAttribute"];
    [[BugSplat shared] setValue:[NSString stringWithFormat:@"Launch Date <![CDATA[%@]]> Value", [NSDate date]] forAttribute:@"CDATAExample"];
    [[BugSplat shared] setValue:[NSString stringWithFormat:@"<!-- 'value is > or < before' --> %@", [NSDate date]] forAttribute:@"CommentExample"];
    [[BugSplat shared] setValue:@"This value will get XML escaping because of 'this' and & and < and >" forAttribute:@"EscapingExample"];
    
    // Don't forget to call start after you've finished configuring BugSplat
    [[BugSplat shared] start];

    return YES;
}

#pragma mark - Sample Log File

/// Creates a sample log file in the documents directory for attachment demonstration
- (void)createSampleLogFile {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSURL *> *urls = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    
    if (urls.count == 0) {
        NSLog(@"Could not access documents directory");
        return;
    }
    
    NSURL *documentsURL = urls.firstObject;
    self.logFileURL = [documentsURL URLByAppendingPathComponent:@"sample_log.txt"];
    
    UIDevice *device = [UIDevice currentDevice];
    NSDate *now = [NSDate date];
    
    NSString *logContent = [NSString stringWithFormat:
        @"=====================================\n"
        @"BugSplat Sample Log File\n"
        @"=====================================\n"
        @"App Launch: %@\n"
        @"Device: %@\n"
        @"System Version: %@\n"
        @"\n"
        @"This is a sample log file demonstrating how to attach\n"
        @"files to BugSplat crash reports.\n"
        @"\n"
        @"You can use this pattern to attach:\n"
        @"- Application logs\n"
        @"- Configuration files\n"
        @"- User session data\n"
        @"- Any other relevant debugging information\n"
        @"\n"
        @"Log entries:\n"
        @"[%@] INFO: Application started\n"
        @"[%@] DEBUG: BugSplat initialized\n"
        @"[%@] INFO: Sample log file created for attachment demo\n"
        @"=====================================\n",
        now, device.model, device.systemVersion, now, now, now];
    
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


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
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

/// Returns a file attachment to include with the crash report
/// This demonstrates how to attach log files or other data to crash reports
- (BugSplatAttachment *)attachmentForBugSplat:(BugSplat *)bugSplat {
    if (!self.logFileURL) {
        NSLog(@"Could not read log file for attachment - no URL");
        return nil;
    }
    
    NSError *error = nil;
    NSData *logData = [NSData dataWithContentsOfURL:self.logFileURL options:0 error:&error];
    
    if (!logData) {
        NSLog(@"Could not read log file for attachment: %@", error.localizedDescription);
        return nil;
    }
    
    NSLog(@"Attaching log file to crash report: %@", self.logFileURL.lastPathComponent);
    return [[BugSplatAttachment alloc] initWithFilename:@"sample_log.txt"
                                         attachmentData:logData
                                            contentType:@"text/plain"];
}

@end
