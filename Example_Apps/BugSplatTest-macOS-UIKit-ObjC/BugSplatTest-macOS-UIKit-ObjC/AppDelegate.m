//
//  AppDelegate.m
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "AppDelegate.h"
#import "BugSplat/BugSplat.h"

/// How long to keep per-session log files before pruning them at startup.
/// Sessions that end normally never trigger bugSplatDidFinishSendingCrashReport:sessionID:
/// (there is no crash report to deliver), so their logs must be cleaned up by age instead.
static const NSTimeInterval kSessionLogMaxAge = 7 * 24 * 60 * 60; // 7 days

@interface AppDelegate () <BugSplatDelegate>

/// URL for the current session's log file. The file is named after BugSplat's
/// per-launch sessionID — that name IS the session-to-log mapping, which is what
/// lets the crashed session's log be found again at the next launch.
@property (nonatomic, strong) NSURL *sessionLogFileURL;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Install a minimal Edit menu so NSTextField gets standard keyboard
    // shortcuts (Cmd+A select-all, Cmd+C/V/X). The storyboard's MainMenu
    // only ships an App menu + Window menu, so without this Cmd+A in the
    // feedback sheet is dead.
    [self installEditMenu];

    // Initialize BugSplat
    [[BugSplat shared] setDelegate:self];
    [[BugSplat shared] setAutoSubmitCrashReport:NO];

    // if user enters name and email, store in in NSUserDefaults for use on subsequent crahes
    [[BugSplat shared] setPersistUserDetails:YES];

    // Optionally, set an appKey to identify this build/environment.
    // This can be used in the BugSplat dashboard to return custom localized support responses.
    [[BugSplat shared] setAppKey:@"en-US"];

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
    // WHY: crash reports are processed at the NEXT launch. A fixed log path that is
    // overwritten on every launch can never be recovered for the session that crashed —
    // by the time the report is sent, the file already holds the new session's log.
    // Naming the file after the sessionID lets attachmentsForBugSplat:sessionID: look up
    // exactly the crashed session's log when the SDK passes that ID back to the delegate.
    [self createSessionLogFile];

    // Clean up logs from old sessions. Sessions that end normally never get the
    // delete-on-delivery callback, so their logs are pruned by age at startup.
    [self pruneOldSessionLogs];
}

#pragma mark - Edit Menu

- (void)installEditMenu {
    NSMenu *mainMenu = [NSApp mainMenu];
    if ([mainMenu indexOfItemWithTitle:@"Edit"] >= 0) return;

    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut"        action:@selector(cut:)       keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy"       action:@selector(copy:)      keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste"      action:@selector(paste:)     keyEquivalent:@"v"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    editItem.submenu = editMenu;

    NSInteger windowIdx = [mainMenu indexOfItemWithTitle:@"Window"];
    if (windowIdx >= 0) {
        [mainMenu insertItem:editItem atIndex:windowIdx];
    } else {
        [mainMenu addItem:editItem];
    }
}

#pragma mark - Per-Session Log Files

/// Directory where per-session log files live: <Application Support>/SessionLogs/
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
/// log lines. A real app would keep appending to this file as the session runs, so
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
        @"\n"
        @"This log file is named after BugSplat's per-launch sessionID.\n"
        @"If this session crashes, the crash report is processed at the\n"
        @"NEXT launch, and BugSplat passes this session's ID back to the\n"
        @"delegate so this exact file can be attached to the report.\n"
        @"\n"
        @"You can use this pattern to attach:\n"
        @"- Application logs\n"
        @"- User session data\n"
        @"- Any other session-scoped debugging information\n"
        @"\n"
        @"Log entries:\n"
        @"[%@] INFO: Application started\n"
        @"[%@] DEBUG: BugSplat initialized\n"
        @"[%@] INFO: Session log file created\n"
        @"=====================================\n",
        sessionID.UUIDString, now, processInfo.hostName, processInfo.operatingSystemVersionString, now, now, now];

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
            NSLog(@"Pruning old session log: %@", logFile.lastPathComponent);
            [fileManager removeItemAtURL:logFile error:nil];
        }
    }
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

#pragma mark - BugSplatDelegate

/// sessionID identifies the session the crash report being sent was recorded in,
/// or nil if the report was recorded by an SDK version that predates session tracking.
- (void)bugSplatWillSendCrashReport:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID {
    NSLog(@"bugSplatWillSendCrashReport:sessionID: %@ called", sessionID.UUIDString);
}

- (void)bugSplatWillSendCrashReportsAlways:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillSendCrashReportsAlways called");
}

- (void)bugSplatWillCancelSendingCrashReport:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillCancelSendingCrashReport called");
}

- (void)bugSplatWillShowSubmitCrashReportAlert:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillShowSubmitCrashReportAlert called");
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
        NSLog(@"No sessionID for crash report - skipping log attachment");
        return @[];
    }

    NSURL *logFileURL = [self logFileURLForSessionID:sessionID];
    NSError *error = nil;
    NSData *logData = [NSData dataWithContentsOfURL:logFileURL options:0 error:&error];

    if (!logData) {
        NSLog(@"Could not read log file for crashed session %@: %@", sessionID.UUIDString, error.localizedDescription);
        return @[];
    }

    NSLog(@"Attaching log file for crashed session %@ to crash report", sessionID.UUIDString);
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:@"session.log"
                                                                   attachmentData:logData
                                                                      contentType:@"text/plain"];
    return @[attachment];
}

/// The crash report was delivered, so the crashed session's log has served its purpose —
/// delete it. This is invoked once per report, so the right log is removed even when
/// several queued crash reports are uploaded during a single launch.
- (void)bugSplatDidFinishSendingCrashReport:(BugSplat *)bugSplat sessionID:(NSUUID *)sessionID {
    NSLog(@"bugSplatDidFinishSendingCrashReport:sessionID: %@ called", sessionID.UUIDString);

    if (!sessionID) {
        return;
    }

    NSURL *logFileURL = [self logFileURLForSessionID:sessionID];
    NSError *error = nil;
    if ([[NSFileManager defaultManager] removeItemAtURL:logFileURL error:&error]) {
        NSLog(@"Deleted delivered session log: %@", logFileURL.lastPathComponent);
    } else {
        NSLog(@"Could not delete session log %@: %@", logFileURL.lastPathComponent, error.localizedDescription);
    }
}

/// The upload failed — deliberately keep the session's log file. BugSplat retries
/// delivery on a future launch and will ask for this session's attachments again.
- (void)bugSplat:(BugSplat *)bugSplat didFailWithError:(NSError *)error sessionID:(NSUUID *)sessionID {
    NSLog(@"bugSplat:didFailWithError: %@ sessionID: %@", [error localizedDescription], sessionID.UUIDString);
}

@end
