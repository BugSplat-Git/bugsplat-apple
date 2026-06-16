//
//  AppDelegate.m
//  BugSplatTest-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "AppDelegate.h"
#import "BugSplat/BugSplat.h"

/// How long a session log is kept before being pruned at startup.
/// Sessions that end normally never receive bugSplatDidFinishSendingCrashReport:sessionID:,
/// so their logs must eventually be cleaned up some other way.
static const NSTimeInterval kSessionLogMaxAge = 7 * 24 * 60 * 60;  // 7 days

@interface AppDelegate () <BugSplatDelegate>

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.

    // Initialize BugSplat
    [[BugSplat shared] setDelegate:self];
    // Enable user prompt for crash reports (default is YES for silent reporting)
    // When set to NO, users see Send/Don't Send/Always Send options
    [[BugSplat shared] setAutoSubmitCrashReport:NO];

    // Optionally, add some attributes to your crash reports.
    // Attributes are artibrary key/value pairs that are searchable in the BugSplat dashboard.
    [[BugSplat shared] setValue:@"Value of Plain Attribute" forAttribute:@"PlainAttribute"];
    [[BugSplat shared] setValue:@"Value of not so plain <value> Attribute" forAttribute:@"NotSoPlainAttribute"];
    [[BugSplat shared] setValue:[NSString stringWithFormat:@"Launch Date <![CDATA[%@]]> Value", [NSDate date]] forAttribute:@"CDATAExample"];
    [[BugSplat shared] setValue:[NSString stringWithFormat:@"<!-- 'value is > or < before' --> %@", [NSDate date]] forAttribute:@"CommentExample"];
    [[BugSplat shared] setValue:@"This value will get XML escaping because of 'this' and & and < and >" forAttribute:@"EscapingExample"];

    // Opt in to fatal hang detection.
    [[BugSplat shared] setEnableHangDetection:YES];

    // Don't forget to call start after you've finished configuring BugSplat
    [[BugSplat shared] start];

    // Create this session's log file, named after BugSplat's per-launch sessionID.
    //
    // WHY per-session file naming matters: crash reports are processed at the NEXT
    // launch of the app, after a brand new session (with a new sessionID and a new
    // log file) has already begun. A single fixed log path that gets overwritten
    // every launch would no longer contain the crashed session's log by the time
    // the SDK asks for an attachment. By naming each log file after its sessionID,
    // the file name itself records the session-to-log mapping, and the crashed
    // session's log can be looked up exactly via the sessionID the SDK passes to
    // the delegate callbacks below.
    [self createSessionLogFileForSessionID:[BugSplat shared].sessionID];

    // Prune session logs from sessions that ended long ago. Sessions that exit
    // normally never crash, so their logs are never cleaned up by the delegate
    // callbacks — without pruning they would accumulate forever.
    [self pruneStaleSessionLogsWithCurrentSessionID:[BugSplat shared].sessionID];

    return YES;
}

#pragma mark - Per-Session Log Files

/// Directory holding one log file per app session: <Application Support>/SessionLogs/<sessionID>.log
- (NSString *)sessionLogsDirectoryPath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);

    if (paths.count == 0) {
        NSLog(@"Could not access Application Support directory");
        return nil;
    }

    return [paths.firstObject stringByAppendingPathComponent:@"SessionLogs"];
}

/// Returns the log file path for a given session ID.
/// The file NAME is the session-to-log mapping — no extra bookkeeping required.
- (NSString *)logFilePathForSessionID:(NSUUID *)sessionID {
    NSString *directoryPath = [self sessionLogsDirectoryPath];

    if (!directoryPath) {
        return nil;
    }

    NSString *filename = [sessionID.UUIDString stringByAppendingPathExtension:@"log"];
    return [directoryPath stringByAppendingPathComponent:filename];
}

/// Creates this session's log file and writes a few sample log lines to it.
/// In a real app, you would route your logging framework's output to this file
/// and append to it throughout the session.
- (void)createSessionLogFileForSessionID:(NSUUID *)sessionID {
    NSString *directoryPath = [self sessionLogsDirectoryPath];
    NSString *logFilePath = [self logFilePathForSessionID:sessionID];

    if (!directoryPath || !logFilePath) {
        return;
    }

    UIDevice *device = [UIDevice currentDevice];
    NSDate *now = [NSDate date];

    NSString *logContent = [NSString stringWithFormat:
        @"=====================================\n"
        @"BugSplat Per-Session Log File\n"
        @"=====================================\n"
        @"Session ID: %@\n"
        @"App Launch: %@\n"
        @"Device: %@\n"
        @"System Version: %@\n"
        @"\n"
        @"This log file is named after BugSplat's per-launch sessionID.\n"
        @"If this session crashes, the crash report is processed at the\n"
        @"NEXT launch, and the SDK passes this session's ID back to the\n"
        @"BugSplatDelegate so exactly this file can be attached.\n"
        @"\n"
        @"Log entries:\n"
        @"[%@] INFO: Application started\n"
        @"[%@] DEBUG: BugSplat initialized\n"
        @"[%@] INFO: Session log file created for session %@\n"
        @"=====================================\n",
        sessionID.UUIDString, now, device.model, device.systemVersion, now, now, now, sessionID.UUIDString];

    NSError *error = nil;

    // Create the SessionLogs directory if it doesn't already exist
    BOOL directoryCreated = [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                                                      withIntermediateDirectories:YES
                                                                       attributes:nil
                                                                            error:&error];
    if (!directoryCreated) {
        NSLog(@"Failed to create SessionLogs directory: %@", error.localizedDescription);
        return;
    }

    BOOL success = [logContent writeToFile:logFilePath
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:&error];

    if (success) {
        NSLog(@"Session log file created at: %@", logFilePath);
    } else {
        NSLog(@"Failed to create session log file: %@", error.localizedDescription);
    }
}

/// Deletes session logs older than kSessionLogMaxAge, never touching the current
/// session's log. Sessions that end normally never get a
/// bugSplatDidFinishSendingCrashReport:sessionID: callback (there is no crash
/// report to send), so this startup sweep is what keeps the directory bounded.
- (void)pruneStaleSessionLogsWithCurrentSessionID:(NSUUID *)currentSessionID {
    NSString *directoryPath = [self sessionLogsDirectoryPath];

    if (!directoryPath) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *filenames = [fileManager contentsOfDirectoryAtPath:directoryPath error:nil];

    if (!filenames) {
        return;  // Directory doesn't exist yet — nothing to prune
    }

    NSDate *cutoffDate = [NSDate dateWithTimeIntervalSinceNow:-kSessionLogMaxAge];
    NSString *currentLogFilename = [currentSessionID.UUIDString stringByAppendingPathExtension:@"log"];

    for (NSString *filename in filenames) {
        // Never delete the log for the session that is running right now
        if ([filename isEqualToString:currentLogFilename]) {
            continue;
        }

        NSString *logFilePath = [directoryPath stringByAppendingPathComponent:filename];
        NSDate *modificationDate = [fileManager attributesOfItemAtPath:logFilePath error:nil][NSFileModificationDate];

        if (!modificationDate || [modificationDate compare:cutoffDate] != NSOrderedAscending) {
            continue;
        }

        NSError *error = nil;
        if ([fileManager removeItemAtPath:logFilePath error:&error]) {
            NSLog(@"Pruned stale session log: %@", filename);
        } else {
            NSLog(@"Failed to prune session log %@: %@", filename, error.localizedDescription);
        }
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

/// The sessionID is the ID of the session that CRASHED (a previous launch),
/// not the current session — when implemented, this is called instead of
/// the legacy bugSplatWillSendCrashReport:.
- (void)bugSplatWillSendCrashReport:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID {
    NSLog(@"bugSplatWillSendCrashReport:sessionID: called with sessionID: %@", sessionID.UUIDString);
}

- (void)bugSplatWillSendCrashReportsAlways:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillSendCrashReportsAlways called");
}

/// The crash report for the given session was delivered, so its log file is no
/// longer needed — delete it. This is invoked once per report, so when several
/// queued reports upload in a single launch, each crashed session's log is
/// cleaned up individually and correctly.
- (void)bugSplatDidFinishSendingCrashReport:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID {
    NSLog(@"bugSplatDidFinishSendingCrashReport:sessionID: called with sessionID: %@", sessionID.UUIDString);

    if (!sessionID) {
        return;
    }

    NSString *logFilePath = [self logFilePathForSessionID:sessionID];

    if (!logFilePath) {
        return;
    }

    NSError *error = nil;
    if ([[NSFileManager defaultManager] removeItemAtPath:logFilePath error:&error]) {
        NSLog(@"Deleted delivered session log: %@", logFilePath.lastPathComponent);
    } else {
        NSLog(@"Failed to delete session log %@: %@", logFilePath.lastPathComponent, error.localizedDescription);
    }
}

- (void)bugSplatWillCancelSendingCrashReport:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillCancelSendingCrashReport called");
}

- (void)bugSplatWillShowSubmitCrashReportAlert:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillShowSubmitCrashReportAlert called");
}

/// Sending the crash report failed. Deliberately KEEP the session's log file —
/// the SDK will retry the upload on a future launch and will ask for the
/// attachment again via attachmentForBugSplat:sessionID:.
- (void)bugSplat:(BugSplat *)bugSplat didFailWithError:(NSError *)error sessionID:(NSUUID *)sessionID {
    NSLog(@"bugSplat:didFailWithError:sessionID: %@, sessionID: %@", [error localizedDescription], sessionID.UUIDString);
}

/// Returns the crashed session's log file as an attachment for the crash report.
/// The sessionID identifies which previous session crashed, and because each
/// session's log is named <sessionID>.log, looking up the right file is just
/// a path construction — this is the payoff of per-session file naming.
- (BugSplatAttachment *)attachmentForBugSplat:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID {
    // sessionID is nil for crash reports recorded by older SDK versions that
    // predate session tracking. A real app could fall back to a heuristic here
    // (e.g. attach the most recent log that isn't the current session's).
    if (!sessionID) {
        NSLog(@"No sessionID for crash report — no session log attached");
        return nil;
    }

    NSString *logFilePath = [self logFilePathForSessionID:sessionID];

    if (!logFilePath) {
        return nil;
    }

    NSError *error = nil;
    NSData *logData = [NSData dataWithContentsOfFile:logFilePath options:0 error:&error];

    if (!logData) {
        // The crashed session's log is missing (e.g. already pruned)
        NSLog(@"Could not read session log for session %@: %@", sessionID.UUIDString, error.localizedDescription);
        return nil;
    }

    NSLog(@"Attaching session log to crash report: %@", logFilePath.lastPathComponent);
    return [[BugSplatAttachment alloc] initWithFilename:@"session.log"
                                         attachmentData:logData
                                            contentType:@"text/plain"];
}

@end
