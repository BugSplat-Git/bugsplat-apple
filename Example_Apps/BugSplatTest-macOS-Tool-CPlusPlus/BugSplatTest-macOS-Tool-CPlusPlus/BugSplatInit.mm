//
//  BugSplatInit.cpp
//  BugSplatTest-macOS-Tool-CPlusPlus
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#include "BugSplatInit.hpp"

#import <AppKit/AppKit.h> // for NSApplicationDidFinishLaunchingNotification
#import <BugSplat/BugSplat.h>

/// How long to keep per-session log files before pruning them at startup.
/// Sessions that end normally never trigger bugSplatDidFinishSendingCrashReport:sessionID:
/// (there is no crash report to deliver), so their logs must be cleaned up by age instead.
static const NSTimeInterval kSessionLogMaxAge = 7 * 24 * 60 * 60; // 7 days

@interface MyBugSplatDelegate : NSObject <BugSplatDelegate>

/// URL for the current session's log file. The file is named after BugSplat's
/// per-launch sessionID — that name IS the session-to-log mapping, which is what
/// lets the crashed session's log be found again at the next launch.
@property (nonatomic, strong) NSURL *sessionLogFileURL;

/// Creates this session's log file, named after BugSplat's sessionID.
/// Must be called after [[BugSplat shared] start] so the sessionID is available.
- (void)createSessionLogFile;

/// Deletes session logs older than kSessionLogMaxAge (never the current session's)
- (void)pruneOldSessionLogs;

@end

// BugSplat holds its delegate weakly, so the delegate must be kept alive
// for the lifetime of the process to receive callbacks
static MyBugSplatDelegate *gBugSplatDelegate = nil;


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
        gBugSplatDelegate = [[MyBugSplatDelegate alloc] init];

        // Set a BugSplatDelegate
        [[BugSplat shared] setDelegate:gBugSplatDelegate];

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

        // Opt in to fatal hang detection.
        [[BugSplat shared] setEnableHangDetection:YES];

        // Don't forget to call start after you've finished configuring BugSplat
        [[BugSplat shared] start];

        // Create this session's log file, named after BugSplat's per-launch sessionID.
        // WHY: crash reports are processed at the NEXT launch of the tool. A fixed log
        // path that is overwritten on every launch can never be recovered for the session
        // that crashed — by the time the report is sent, the file already holds the new
        // session's log. Naming the file after the sessionID lets
        // attachmentsForBugSplat:sessionID: look up exactly the crashed session's log
        // when BugSplat passes that ID back to the delegate.
        // NOTE: must come after [[BugSplat shared] start] so the sessionID is available.
        [gBugSplatDelegate createSessionLogFile];

        // Clean up logs from old sessions. Sessions that end normally never get the
        // delete-on-delivery callback, so their logs are pruned by age at startup.
        [gBugSplatDelegate pruneOldSessionLogs];

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

int bugSplatSendFeedback(std::string title, std::string description)
{
    @autoreleasepool {
        NSString *titleString = @(title.c_str());
        NSString *descriptionString = @(description.c_str());
        NSLog(@"bugSplatSendFeedback(%@, %@)", titleString, descriptionString);

        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSError *feedbackError = nil;

        [[BugSplat shared] postFeedback:titleString
                            description:descriptionString
                               userName:nil
                              userEmail:nil
                                 appKey:nil
                            attachments:nil
                             completion:^(NSError * _Nullable error) {
            feedbackError = error;
            dispatch_semaphore_signal(semaphore);
        }];

        // Give the run loop time to process the network request
        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW)) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }

        if (feedbackError) {
            NSLog(@"Feedback failed: %@", feedbackError.localizedDescription);
            return 1;
        } else {
            NSLog(@"Feedback submitted successfully!");
            return 0;
        }
    }
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

#pragma mark - Per-Session Log Files

/// Directory where per-session log files live: <Application Support>/SessionLogs/
/// For a command line tool, Application Support in the user domain (~/Library/Application Support) is used
- (NSURL *)sessionLogsDirectoryURL {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSURL *> *urls = [fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];

    if (urls.count == 0) {
        NSLog(@"Could not access Application Support directory");
        return nil;
    }

    return [urls.firstObject URLByAppendingPathComponent:@"SessionLogs" isDirectory:YES];
}

/// Log file URL for a given session ID: SessionLogs/<uuid>.log
/// The file name itself is the session-to-log mapping — no extra bookkeeping
/// (databases, plists, etc.) is needed to find the right log later.
- (NSURL *)logFileURLForSessionID:(NSUUID *)sessionID {
    NSString *fileName = [NSString stringWithFormat:@"%@.log", sessionID.UUIDString];
    return [[self sessionLogsDirectoryURL] URLByAppendingPathComponent:fileName];
}

/// Creates this session's log file (named <sessionID>.log) and writes a few sample
/// log lines. A real tool would keep appending to this file as the session runs, so
/// that a crash report carries everything logged up to the moment of the crash.
- (void)createSessionLogFile {
    // sessionID is generated by BugSplat at every launch and is stable for the
    // lifetime of the process. It is embedded in any crash report captured during
    // this session — which is what ties this file to a future crash report.
    NSUUID *sessionID = [[BugSplat shared] sessionID];

    NSURL *directoryURL = [self sessionLogsDirectoryURL];
    if (!directoryURL) {
        return;
    }

    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"Failed to create SessionLogs directory: %@", error.localizedDescription);
        return;
    }

    self.sessionLogFileURL = [self logFileURLForSessionID:sessionID];

    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    NSDate *now = [NSDate date];

    NSString *logContent = [NSString stringWithFormat:
        @"=====================================\n"
        @"BugSplat Per-Session Log File\n"
        @"=====================================\n"
        @"Session ID: %@\n"
        @"App Launch: %@\n"
        @"Host Name: %@\n"
        @"OS Version: %@\n"
        @"Process Name: %@\n"
        @"Process ID: %d\n"
        @"\n"
        @"This log file is named after BugSplat's per-launch sessionID.\n"
        @"If this session crashes, the crash report is processed at the\n"
        @"NEXT launch of the tool, and BugSplat passes this session's ID\n"
        @"back to the delegate so this exact file can be attached.\n"
        @"\n"
        @"You can use this pattern to attach:\n"
        @"- Application logs\n"
        @"- Diagnostic data\n"
        @"- Any other session-scoped debugging information\n"
        @"\n"
        @"Log entries:\n"
        @"[%@] INFO: Command line tool started\n"
        @"[%@] DEBUG: BugSplat initialized\n"
        @"[%@] INFO: Session log file created\n"
        @"=====================================\n",
        sessionID.UUIDString, now, processInfo.hostName, processInfo.operatingSystemVersionString,
        processInfo.processName, processInfo.processIdentifier, now, now, now];

    BOOL success = [logContent writeToURL:self.sessionLogFileURL
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&error];

    if (success) {
        NSLog(@"Session log file created at: %@", self.sessionLogFileURL.path);
    } else {
        NSLog(@"Failed to create session log file: %@", error.localizedDescription);
        self.sessionLogFileURL = nil;
    }
}

/// Deletes session logs older than kSessionLogMaxAge. Logs for crashed sessions are
/// deleted as soon as their report is delivered (see bugSplatDidFinishSendingCrashReport:sessionID:),
/// but sessions that end normally leave their log behind, so prune by age here.
/// The current session's log is never deleted.
- (void)pruneOldSessionLogs {
    NSURL *directoryURL = [self sessionLogsDirectoryURL];
    if (!directoryURL) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSURL *> *logFiles = [fileManager contentsOfDirectoryAtURL:directoryURL
                                            includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 error:nil];

    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-kSessionLogMaxAge];
    for (NSURL *logFile in logFiles) {
        // Never delete the log for the session currently in progress
        if ([logFile.lastPathComponent isEqualToString:self.sessionLogFileURL.lastPathComponent]) {
            continue;
        }

        NSDate *modificationDate = nil;
        [logFile getResourceValue:&modificationDate forKey:NSURLContentModificationDateKey error:nil];

        if (modificationDate && [modificationDate compare:cutoff] == NSOrderedAscending) {
            NSLog(@"*** Pruning old session log: %@", logFile.lastPathComponent);
            [fileManager removeItemAtURL:logFile error:nil];
        }
    }
}

#pragma mark - BugSplatDelegate

/// sessionID identifies the session the crash report being sent was recorded in,
/// or nil if the report was recorded by an SDK version that predates session tracking.
- (void)bugSplatWillSendCrashReport:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    NSLog(@"*** bugSplatWillSendCrashReport:sessionID: %@", sessionID.UUIDString);
}

/// The upload failed — deliberately keep the session's log file. BugSplat retries
/// delivery on a future launch and will ask for this session's attachments again.
- (void)bugSplat:(BugSplat *)bugSplat didFailWithError:(NSError *)error sessionID:(NSUUID *)sessionID
{
    NSLog(@"*** bugSplat:didFailWithError: %@ sessionID: %@", error.debugDescription, sessionID.UUIDString);
}

/// The crash report was delivered, so the crashed session's log has served its purpose —
/// delete it. This is invoked once per report, so the right log is removed even when
/// several queued crash reports are uploaded during a single launch.
- (void)bugSplatDidFinishSendingCrashReport:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID
{
    NSLog(@"*** bugSplatDidFinishSendingCrashReport:sessionID: %@", sessionID.UUIDString);

    if (!sessionID) {
        return;
    }

    NSURL *logFileURL = [self logFileURLForSessionID:sessionID];
    NSError *error = nil;
    if ([[NSFileManager defaultManager] removeItemAtURL:logFileURL error:&error]) {
        NSLog(@"*** Deleted delivered session log: %@", logFileURL.lastPathComponent);
    } else {
        NSLog(@"*** Could not delete session log %@: %@", logFileURL.lastPathComponent, error.localizedDescription);
    }
}

-(void)bugSplatWillShowSubmitCrashReportAlert:(BugSplat *)bugSplat
{
    NSLog(@"*** bugSplatWillShowSubmitCrashReportAlert");
}

-(void)bugSplatWillCancelSendingCrashReport:(BugSplat *)bugSplat
{
    NSLog(@"*** bugSplatWillCancelSendingCrashReport");
}

/// Returns an array of file attachments to include with the crash report.
/// The sessionID identifies the session that CRASHED — not the current one —
/// so the matching per-session log file can be located simply by its name.
/// Note: macOS supports multiple attachments, unlike iOS which only supports one
- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID {
    if (!sessionID) {
        // Crash reports recorded by SDK versions that predate session tracking carry
        // no session ID. An app could fall back to a heuristic here (e.g. attach the
        // most recent log file that isn't the current session's).
        NSLog(@"*** No sessionID for crash report - skipping log attachment");
        return @[];
    }

    NSURL *logFileURL = [self logFileURLForSessionID:sessionID];
    NSError *error = nil;
    NSData *logData = [NSData dataWithContentsOfURL:logFileURL options:0 error:&error];

    if (!logData) {
        NSLog(@"*** Could not read log file for crashed session %@: %@", sessionID.UUIDString, error.localizedDescription);
        return @[];
    }

    NSLog(@"*** Attaching log file for crashed session %@ to crash report", sessionID.UUIDString);
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:@"session.log"
                                                                   attachmentData:logData
                                                                      contentType:@"text/plain"];
    return @[attachment];
}

@end
