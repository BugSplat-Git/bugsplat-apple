//
//  BugSplat.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#if TARGET_OS_OSX
#import <BugSplatMac/BugSplat.h>
#else
#import <BugSplat/BugSplat.h>
#endif

#import <CrashReporter/CrashReporter.h>
#import "BugSplatUtilities.h"
#import "BugSplatUploadService.h"
#import "BugSplatZipHelper.h"

#if TARGET_OS_OSX
#import "BugSplatCrashReportWindow.h"
#else
#import <UIKit/UIKit.h>
#endif

NSString *const kBugSplatUserDefaultsUserID = @"com.bugsplat.userID";
NSString *const kBugSplatUserDefaultsUserName = @"com.bugsplat.userName";
NSString *const kBugSplatUserDefaultsUserEmail = @"com.bugsplat.userEmail";
NSString *const kBugSplatUserDefaultsAttributes = @"com.bugsplat.attributes";
NSString *const kBugSplatUserDefaultsAlwaysSend = @"com.bugsplat.alwaysSend";

// File extensions for persisted crash data
static NSString *const kBugSplatCrashFileExtension = @"crash";
static NSString *const kBugSplatMetaFileExtension = @"meta";
static NSString *const kBugSplatAttachmentFileExtension = @"data";

// Keys for crash metadata
static NSString *const kBugSplatMetaKeyUserName = @"userName";
static NSString *const kBugSplatMetaKeyUserEmail = @"userEmail";
static NSString *const kBugSplatMetaKeyComments = @"comments";
static NSString *const kBugSplatMetaKeyAttributes = @"attributes";
static NSString *const kBugSplatMetaKeyApplicationLog = @"applicationLog";
static NSString *const kBugSplatMetaKeyApplicationKey = @"applicationKey";
static NSString *const kBugSplatMetaKeyTimestamp = @"timestamp";

@interface BugSplat ()

@property (atomic, assign) BOOL isStartInvoked;
@property (atomic, assign) BOOL sendingInProgress;
@property (nonatomic, nullable) NSDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, strong) PLCrashReporter *crashReporter;
@property (nonatomic, strong, nullable) BugSplatUploadService *uploadService;
@property (nonatomic, copy, nullable) NSString *currentCrashFilename;

#if TARGET_OS_OSX
@property (nonatomic, strong, nullable) BugSplatCrashReportWindow *crashReportWindow;
#endif

@end

@implementation BugSplat
{
    NSString *_bugSplatDatabase;
    NSString *_applicationName;
    NSString *_applicationVersion;
}

+ (instancetype)shared
{
    static BugSplat *sharedInstance = nil;
    static dispatch_once_t pred;
    
    dispatch_once(&pred, ^{
        sharedInstance = [[BugSplat alloc] init];

        // Load and erase any persisted attributes from previous session
        sharedInstance.attributes = [NSUserDefaults.standardUserDefaults dictionaryForKey:kBugSplatUserDefaultsAttributes];
        [NSUserDefaults.standardUserDefaults setValue:nil forKey:kBugSplatUserDefaultsAttributes];
    });
    
    return sharedInstance;
}

- (instancetype)init
{
    if (self = [super init]) {
        self.isStartInvoked = NO;
        self.sendingInProgress = NO;
        self.currentCrashFilename = nil;

        // Configure PLCrashReporter
        // Note: Mach exception handling is not available on tvOS, use BSD signal handling instead
#if TARGET_OS_TV
        PLCrashReporterSignalHandlerType signalHandlerType = PLCrashReporterSignalHandlerTypeBSD;
#else
        PLCrashReporterSignalHandlerType signalHandlerType = PLCrashReporterSignalHandlerTypeMach;
#endif
        PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc]
            initWithSignalHandlerType:signalHandlerType
            symbolicationStrategy:PLCrashReporterSymbolicationStrategyNone];
        
        _crashReporter = [[PLCrashReporter alloc] initWithConfiguration:config];

#if TARGET_OS_OSX
        _autoSubmitCrashReport = NO;
        _askUserDetails = YES;
        _expirationTimeInterval = -1;

        NSImage *bannerImage = [NSImage imageNamed:@"bugsplat-logo"];
        if (bannerImage) {
            _bannerImage = bannerImage;
        }
#else
        // iOS: Default to silent crash reporting (no user prompt)
        // Set to NO to prompt users with Send/Don't Send/Always Send options
        _autoSubmitCrashReport = YES;
#endif
    }

    return self;
}

- (void)start
{
    NSLog(@"BugSplat start...");

    if (!self.bugSplatDatabase) {
        NSLog(@"*** BugSplatDatabase is nil. Please add this key/value to your app's Info.plist or set bugSplatDatabase before invoking start. ***");
        NSAssert(NO, @"*** BugSplatDatabase is nil. Please add this key/value to your app's Info.plist or set bugSplatDatabase before invoking start. ***");
        self.isStartInvoked = NO;
        return;
    }

    if (self.isStartInvoked) {
        NSLog(@"*** BugSplat `start` was already invoked. ***");
        return;
    }

    NSLog(@"BugSplat Database: [%@]", self.bugSplatDatabase);
    NSLog(@"BugSplat Application: [%@] Version: [%@]", self.resolvedApplicationName, self.resolvedApplicationVersion);
    
    // Create upload service
    self.uploadService = [[BugSplatUploadService alloc] initWithDatabase:self.bugSplatDatabase
                                                         applicationName:self.resolvedApplicationName
                                                      applicationVersion:self.resolvedApplicationVersion];
    
    // First, check for any NEW crash report from PLCrashReporter
    // This will persist it to our crashes directory for offline retry support
    if ([self.crashReporter hasPendingCrashReport]) {
        [self handleNewCrashFromPLCrashReporter];
    }
    
    // Then, process any pending crash reports from our crashes directory
    // This includes both new crashes and previously failed uploads
    [self processPendingCrashReports];
    
    // Enable crash reporter for this session
    NSError *error = nil;
    if (![self.crashReporter enableCrashReporterAndReturnError:&error]) {
        NSLog(@"BugSplat: Failed to enable crash reporter: %@", error);
    }
    
    self.isStartInvoked = YES;
}

#pragma mark - Crash Report Handling

/**
 * Handle a new crash from PLCrashReporter.
 * This method copies the crash data to our crashes directory for offline retry support,
 * then purges the PLCrashReporter pending report.
 */
- (void)handleNewCrashFromPLCrashReporter
{
    NSLog(@"BugSplat: Processing new crash report from PLCrashReporter...");
    
    NSError *error = nil;
    NSData *crashData = nil;
    
    @try {
        crashData = [self.crashReporter loadPendingCrashReportDataAndReturnError:&error];
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception loading crash report: %@ - %@", exception.name, exception.reason);
        [self.crashReporter purgePendingCrashReport];
        return;
    }
    
    if (!crashData || crashData.length == 0) {
        NSLog(@"BugSplat: Failed to load crash report: %@", error);
        [self.crashReporter purgePendingCrashReport];
        return;
    }
    
    // Parse crash report to get text representation
    PLCrashReport *crashReport = nil;
    NSString *crashReportText = nil;
    
    @try {
        crashReport = [[PLCrashReport alloc] initWithData:crashData error:&error];
        if (crashReport) {
            crashReportText = [PLCrashReportTextFormatter stringValueForCrashReport:crashReport
                                                                     withTextFormat:PLCrashReportTextFormatiOS];
        }
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception parsing crash report: %@ - %@", exception.name, exception.reason);
    }
    
    // Ensure we have some crash report text
    if (!crashReportText || crashReportText.length == 0) {
        crashReportText = @"[Crash report text unavailable]";
    }
    
    // Generate a unique filename for this crash based on timestamp
    NSString *crashFilename = [NSString stringWithFormat:@"%.0f", [NSDate timeIntervalSinceReferenceDate]];
    self.currentCrashFilename = crashFilename;
    
    // Persist the crash report text to disk
    NSString *crashesDir = [self crashesDirectoryPath];
    if (!crashesDir) {
        NSLog(@"BugSplat: Failed to get crashes directory");
        [self.crashReporter purgePendingCrashReport];
        return;
    }
    
    NSData *textCrashData = [crashReportText dataUsingEncoding:NSUTF8StringEncoding];
    if (!textCrashData) {
        NSLog(@"BugSplat: Failed to encode crash report text");
        [self.crashReporter purgePendingCrashReport];
        return;
    }
    
    NSString *crashFilePath = [[crashesDir stringByAppendingPathComponent:crashFilename] 
                               stringByAppendingPathExtension:kBugSplatCrashFileExtension];
    BOOL writeSuccess = [textCrashData writeToFile:crashFilePath atomically:YES];
    if (!writeSuccess) {
        NSLog(@"BugSplat: Failed to write crash report to disk");
        [self.crashReporter purgePendingCrashReport];
        return;
    }
    
    NSLog(@"BugSplat: Persisted crash report to %@.%@", crashFilename, kBugSplatCrashFileExtension);
    
    // IMMEDIATELY gather attachments from delegate and persist to disk
    // This captures attachment data early, before app state changes
    NSMutableArray<BugSplatAttachment *> *attachments = [NSMutableArray array];
    
    @try {
#if TARGET_OS_OSX
        if ([self.delegate respondsToSelector:@selector(attachmentsForBugSplat:)]) {
            NSArray *delegateAttachments = [self.delegate attachmentsForBugSplat:self];
            if (delegateAttachments) {
                [attachments addObjectsFromArray:delegateAttachments];
            }
        } else
#endif
        if ([self.delegate respondsToSelector:@selector(attachmentForBugSplat:)]) {
            BugSplatAttachment *attachment = [self.delegate attachmentForBugSplat:self];
            if (attachment) {
                [attachments addObject:attachment];
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in delegate attachment method: %@ - %@", exception.name, exception.reason);
    }
    
    // Persist attachments to disk with crash filename prefix
    if (attachments.count > 0) {
        [self persistAttachments:attachments forCrashFilename:crashFilename];
    }
    
    // Build and persist metadata
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    metadata[kBugSplatMetaKeyTimestamp] = @([[NSDate date] timeIntervalSince1970]);
    
    if (self.userName) metadata[kBugSplatMetaKeyUserName] = self.userName;
    if (self.userEmail) metadata[kBugSplatMetaKeyUserEmail] = self.userEmail;
    if (self.attributes) metadata[kBugSplatMetaKeyAttributes] = self.attributes;
    
    // Get application log from delegate
    @try {
        if ([self.delegate respondsToSelector:@selector(applicationLogForBugSplat:)]) {
            NSString *appLog = [self.delegate applicationLogForBugSplat:self];
            if (appLog) metadata[kBugSplatMetaKeyApplicationLog] = appLog;
        }
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in applicationLogForBugSplat delegate: %@ - %@", exception.name, exception.reason);
    }
    
#if TARGET_OS_OSX
    // Get application key from delegate (macOS only)
    @try {
        if ([self.delegate respondsToSelector:@selector(applicationKeyForBugSplat:signal:exceptionName:exceptionReason:)]) {
            NSString *signal = crashReport.signalInfo.name;
            NSString *exceptionName = crashReport.hasExceptionInfo ? crashReport.exceptionInfo.exceptionName : nil;
            NSString *exceptionReason = crashReport.hasExceptionInfo ? crashReport.exceptionInfo.exceptionReason : nil;
            NSString *appKey = [self.delegate applicationKeyForBugSplat:self signal:signal exceptionName:exceptionName exceptionReason:exceptionReason];
            if (appKey) metadata[kBugSplatMetaKeyApplicationKey] = appKey;
        }
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in applicationKeyForBugSplat delegate: %@ - %@", exception.name, exception.reason);
    }
#endif
    
    // Persist metadata
    NSString *metaFilePath = [[crashesDir stringByAppendingPathComponent:crashFilename] 
                              stringByAppendingPathExtension:kBugSplatMetaFileExtension];
    [metadata writeToFile:metaFilePath atomically:YES];
    
    // IMPORTANT: Purge PLCrashReporter's pending report now that we've saved a copy
    // This ensures we don't process the same crash twice
    [self.crashReporter purgePendingCrashReport];
    NSLog(@"BugSplat: Purged PLCrashReporter pending report (copy saved for retry)");
}

/**
 * Process any pending crash reports from our crashes directory.
 * This handles both new crashes and previously failed uploads (offline retry).
 *
 * Following HockeyApp's behavior:
 * - Shows dialog only for the FIRST pending crash (if autoSubmitCrashReport is NO)
 * - After user approves, remaining crashes are sent silently
 * - If autoSubmitCrashReport is YES, all crashes are sent silently
 */
- (void)processPendingCrashReports
{
    [self processPendingCrashReportsShowingDialog:!self.autoSubmitCrashReport];
}

/**
 * Process pending crash reports with control over whether to show a dialog.
 * @param showDialog If YES, shows dialog for the first crash. If NO, sends silently.
 */
- (void)processPendingCrashReportsShowingDialog:(BOOL)showDialog
{
    if (self.sendingInProgress) {
        NSLog(@"BugSplat: Sending already in progress, skipping");
        return;
    }
    
    NSArray<NSString *> *pendingCrashFiles = [self getPendingCrashFiles];
    if (pendingCrashFiles.count == 0) {
        NSLog(@"BugSplat: No pending crash reports found");
        return;
    }
    
    NSLog(@"BugSplat: Found %lu pending crash report(s)", (unsigned long)pendingCrashFiles.count);
    self.sendingInProgress = YES;
    
    // Process the first (oldest) pending crash report
    NSString *crashFilename = pendingCrashFiles.firstObject;
    self.currentCrashFilename = crashFilename;
    
    NSString *crashesDir = [self crashesDirectoryPath];
    NSString *crashFilePath = [[crashesDir stringByAppendingPathComponent:crashFilename] 
                               stringByAppendingPathExtension:kBugSplatCrashFileExtension];
    
    // Load crash report text
    NSData *crashData = [NSData dataWithContentsOfFile:crashFilePath];
    if (!crashData || crashData.length == 0) {
        NSLog(@"BugSplat: Failed to load crash report from %@, cleaning up", crashFilename);
        [self cleanupCrashReportWithFilename:crashFilename];
        self.sendingInProgress = NO;
        // Try next crash report (silently, since we're past the first one)
        [self processPendingCrashReportsShowingDialog:NO];
        return;
    }
    
    NSString *crashReportText = [[NSString alloc] initWithData:crashData encoding:NSUTF8StringEncoding];
    if (!crashReportText) {
        NSLog(@"BugSplat: Failed to decode crash report text, cleaning up");
        [self cleanupCrashReportWithFilename:crashFilename];
        self.sendingInProgress = NO;
        [self processPendingCrashReportsShowingDialog:NO];
        return;
    }
    
    // Load metadata
    NSString *metaFilePath = [[crashesDir stringByAppendingPathComponent:crashFilename] 
                              stringByAppendingPathExtension:kBugSplatMetaFileExtension];
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metaFilePath];
    
    // Check expiration (macOS only) - expired crashes are auto-submitted silently
#if TARGET_OS_OSX
    @try {
        NSNumber *timestamp = metadata[kBugSplatMetaKeyTimestamp];
        if (self.expirationTimeInterval > 0 && timestamp) {
            NSTimeInterval timeSinceCrash = [[NSDate date] timeIntervalSince1970] - timestamp.doubleValue;
            if (timeSinceCrash > self.expirationTimeInterval) {
                NSLog(@"BugSplat: Crash report expired (%.0f seconds old), auto-submitting...", timeSinceCrash);
                [self submitPersistedCrashReportWithFilename:crashFilename 
                                             crashReportText:crashReportText 
                                                    metadata:metadata 
                                                    userName:self.userName 
                                                   userEmail:self.userEmail 
                                                    comments:nil];
                return;
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception checking crash report expiration: %@ - %@", exception.name, exception.reason);
    }
#endif
    
    // Determine whether to show dialog or auto-submit
#if TARGET_OS_OSX
    if (showDialog) {
        // Show dialog only for the first crash - remaining will be sent silently after user approves
        [self showCrashReportDialogForFilename:crashFilename 
                               crashReportText:crashReportText 
                                      metadata:metadata];
    } else {
        // Send silently (either auto-submit is on, or this is a subsequent crash after user approved the first)
        [self submitPersistedCrashReportWithFilename:crashFilename 
                                     crashReportText:crashReportText 
                                            metadata:metadata 
                                            userName:metadata[kBugSplatMetaKeyUserName] ?: self.userName
                                           userEmail:metadata[kBugSplatMetaKeyUserEmail] ?: self.userEmail
                                            comments:nil];
    }
#else
    // iOS: Check if user has chosen "Always Send" or if we should show the alert
    BOOL alwaysSend = [[NSUserDefaults standardUserDefaults] boolForKey:kBugSplatUserDefaultsAlwaysSend];
    
    if (showDialog && !alwaysSend) {
        // Show alert only for the first crash - remaining will be sent silently after user approves
        [self showCrashReportAlertForFilename:crashFilename 
                              crashReportText:crashReportText 
                                     metadata:metadata];
    } else {
        // Send silently (auto-submit is on, user chose "Always Send", or this is a subsequent crash)
        [self submitPersistedCrashReportWithFilename:crashFilename 
                                     crashReportText:crashReportText 
                                            metadata:metadata 
                                            userName:metadata[kBugSplatMetaKeyUserName] ?: self.userName
                                           userEmail:metadata[kBugSplatMetaKeyUserEmail] ?: self.userEmail
                                            comments:nil];
    }
#endif
}

/**
 * Get list of pending crash report filenames (without extension), sorted oldest first.
 */
- (NSArray<NSString *> *)getPendingCrashFiles
{
    NSString *crashesDir = [self crashesDirectoryPath];
    if (!crashesDir) {
        return @[];
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:crashesDir error:&error];
    if (error || !files) {
        return @[];
    }
    
    NSMutableArray<NSString *> *crashFilenames = [NSMutableArray array];
    NSString *crashExtension = [NSString stringWithFormat:@".%@", kBugSplatCrashFileExtension];
    
    for (NSString *filename in files) {
        if ([filename hasSuffix:crashExtension]) {
            // Extract base filename without extension
            NSString *baseName = [filename stringByDeletingPathExtension];
            [crashFilenames addObject:baseName];
        }
    }
    
    // Sort by filename (which is timestamp-based) to process oldest first
    [crashFilenames sortUsingSelector:@selector(compare:)];
    
    return crashFilenames;
}

#if TARGET_OS_OSX
- (void)showCrashReportDialogForFilename:(NSString *)crashFilename
                         crashReportText:(NSString *)crashReportText
                                metadata:(NSDictionary *)metadata
{
    // Notify delegate (wrapped to prevent crashes in crash handler)
    @try {
        if ([self.delegate respondsToSelector:@selector(bugSplatWillShowSubmitCrashReportAlert:)]) {
            [self.delegate bugSplatWillShowSubmitCrashReportAlert:self];
        }
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in bugSplatWillShowSubmitCrashReportAlert delegate: %@ - %@", exception.name, exception.reason);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            self.crashReportWindow = [[BugSplatCrashReportWindow alloc] init];
            self.crashReportWindow.applicationName = self.resolvedApplicationName;
            self.crashReportWindow.bannerImage = self.bannerImage;
            self.crashReportWindow.crashReportText = crashReportText;
            self.crashReportWindow.askUserDetails = self.askUserDetails;
            
            if (self.persistUserDetails) {
                self.crashReportWindow.prefillUserName = self.userName;
                self.crashReportWindow.prefillUserEmail = self.userEmail;
            }
            
            void (^completionHandler)(BugSplatUserAction, NSString *, NSString *, NSString *) = ^(BugSplatUserAction action, NSString *userName, NSString *userEmail, NSString *comments) {
                @try {
                    if (action == BugSplatUserActionSend) {
                        // Persist user details if enabled
                        if (self.persistUserDetails) {
                            if (userName.length > 0) self.userName = userName;
                            if (userEmail.length > 0) self.userEmail = userEmail;
                        }
                        
                        // Submit this crash with user-provided details
                        // Note: After this completes, remaining crashes will be sent SILENTLY
                        [self submitPersistedCrashReportWithFilename:crashFilename
                                                     crashReportText:crashReportText
                                                            metadata:metadata
                                                            userName:userName
                                                           userEmail:userEmail
                                                            comments:comments];
                    } else {
                        // User cancelled - cleanup ALL pending crash reports (following HockeyApp behavior)
                        @try {
                            if ([self.delegate respondsToSelector:@selector(bugSplatWillCancelSendingCrashReport:)]) {
                                [self.delegate bugSplatWillCancelSendingCrashReport:self];
                            }
                        } @catch (NSException *exception) {
                            NSLog(@"BugSplat: Exception in bugSplatWillCancelSendingCrashReport delegate: %@ - %@", exception.name, exception.reason);
                        }
                        
                        // Cleanup ALL pending crash reports since user declined
                        [self cleanupAllPendingCrashReports];
                        self.attributes = nil;
                        self.sendingInProgress = NO;
                    }
                } @catch (NSException *exception) {
                    NSLog(@"BugSplat: Exception in crash report completion handler: %@ - %@", exception.name, exception.reason);
                    [self cleanupCrashReportWithFilename:crashFilename];
                    self.sendingInProgress = NO;
                }
                
                self.crashReportWindow = nil;
            };
            
            if (self.presentModally) {
                [self.crashReportWindow showModalWithCompletion:completionHandler];
            } else {
                [self.crashReportWindow showWithCompletion:completionHandler];
            }
        } @catch (NSException *exception) {
            NSLog(@"BugSplat: Exception showing crash report dialog: %@ - %@", exception.name, exception.reason);
            // Fall back to auto-submit if dialog fails
            [self submitPersistedCrashReportWithFilename:crashFilename
                                         crashReportText:crashReportText
                                                metadata:metadata
                                                userName:self.userName
                                               userEmail:self.userEmail
                                                comments:nil];
        }
    });
}
#else
// iOS crash report alert implementation
- (void)showCrashReportAlertForFilename:(NSString *)crashFilename
                        crashReportText:(NSString *)crashReportText
                               metadata:(NSDictionary *)metadata
{
    // Notify delegate (wrapped to prevent crashes in crash handler)
    @try {
        if ([self.delegate respondsToSelector:@selector(bugSplatWillShowSubmitCrashReportAlert:)]) {
            [self.delegate bugSplatWillShowSubmitCrashReportAlert:self];
        }
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in bugSplatWillShowSubmitCrashReportAlert delegate: %@ - %@", exception.name, exception.reason);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            NSString *appName = self.resolvedApplicationName;
            NSString *title = [NSString stringWithFormat:@"%@ Quit Unexpectedly", appName];
            NSString *message = @"Would you like to send a crash report so we can fix the problem?";
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                           message:message
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            
            // "Don't Send" action
            UIAlertAction *dontSendAction = [UIAlertAction actionWithTitle:@"Don't Send"
                                                                     style:UIAlertActionStyleCancel
                                                                   handler:^(UIAlertAction *action) {
                @try {
                    if ([self.delegate respondsToSelector:@selector(bugSplatWillCancelSendingCrashReport:)]) {
                        [self.delegate bugSplatWillCancelSendingCrashReport:self];
                    }
                } @catch (NSException *exception) {
                    NSLog(@"BugSplat: Exception in bugSplatWillCancelSendingCrashReport delegate: %@ - %@", exception.name, exception.reason);
                }
                
                // Cleanup ALL pending crash reports since user declined
                [self cleanupAllPendingCrashReports];
                self.attributes = nil;
                self.sendingInProgress = NO;
            }];
            [alert addAction:dontSendAction];
            
            // "Send" action
            UIAlertAction *sendAction = [UIAlertAction actionWithTitle:@"Send"
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction *action) {
                [self submitPersistedCrashReportWithFilename:crashFilename
                                             crashReportText:crashReportText
                                                    metadata:metadata
                                                    userName:metadata[kBugSplatMetaKeyUserName] ?: self.userName
                                                   userEmail:metadata[kBugSplatMetaKeyUserEmail] ?: self.userEmail
                                                    comments:nil];
            }];
            [alert addAction:sendAction];
            
            // "Always Send" action
            UIAlertAction *alwaysSendAction = [UIAlertAction actionWithTitle:@"Always Send"
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^(UIAlertAction *action) {
                // Save the "always send" preference
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kBugSplatUserDefaultsAlwaysSend];
                
                // Notify delegate
                @try {
                    if ([self.delegate respondsToSelector:@selector(bugSplatWillSendCrashReportsAlways:)]) {
                        [self.delegate bugSplatWillSendCrashReportsAlways:self];
                    }
                } @catch (NSException *exception) {
                    NSLog(@"BugSplat: Exception in bugSplatWillSendCrashReportsAlways delegate: %@ - %@", exception.name, exception.reason);
                }
                
                [self submitPersistedCrashReportWithFilename:crashFilename
                                             crashReportText:crashReportText
                                                    metadata:metadata
                                                    userName:metadata[kBugSplatMetaKeyUserName] ?: self.userName
                                                   userEmail:metadata[kBugSplatMetaKeyUserEmail] ?: self.userEmail
                                                    comments:nil];
            }];
            [alert addAction:alwaysSendAction];
            
            // Find the top-most view controller to present the alert
            UIViewController *presentingViewController = [self topMostViewController];
            if (presentingViewController) {
                [presentingViewController presentViewController:alert animated:YES completion:nil];
            } else {
                NSLog(@"BugSplat: Could not find view controller to present crash report alert, auto-submitting...");
                // Fall back to auto-submit if no view controller available
                [self submitPersistedCrashReportWithFilename:crashFilename
                                             crashReportText:crashReportText
                                                    metadata:metadata
                                                    userName:metadata[kBugSplatMetaKeyUserName] ?: self.userName
                                                   userEmail:metadata[kBugSplatMetaKeyUserEmail] ?: self.userEmail
                                                    comments:nil];
            }
        } @catch (NSException *exception) {
            NSLog(@"BugSplat: Exception showing crash report alert: %@ - %@", exception.name, exception.reason);
            // Fall back to auto-submit if alert fails
            [self submitPersistedCrashReportWithFilename:crashFilename
                                         crashReportText:crashReportText
                                                metadata:metadata
                                                userName:self.userName
                                               userEmail:self.userEmail
                                                comments:nil];
        }
    });
}

/**
 * Find the top-most view controller in the app to present the alert.
 */
- (UIViewController *)topMostViewController
{
    UIWindowScene *activeScene = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            activeScene = (UIWindowScene *)scene;
            break;
        }
    }
    
    if (!activeScene) {
        // Fall back to any foreground inactive scene
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundInactive && [scene isKindOfClass:[UIWindowScene class]]) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }
    }
    
    if (!activeScene) {
        return nil;
    }
    
    UIWindow *keyWindow = nil;
    for (UIWindow *window in activeScene.windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    
    if (!keyWindow) {
        keyWindow = activeScene.windows.firstObject;
    }
    
    if (!keyWindow) {
        return nil;
    }
    
    UIViewController *rootViewController = keyWindow.rootViewController;
    return [self topViewControllerWithRootViewController:rootViewController];
}

- (UIViewController *)topViewControllerWithRootViewController:(UIViewController *)rootViewController
{
    if (!rootViewController) {
        return nil;
    }
    
    if (rootViewController.presentedViewController) {
        return [self topViewControllerWithRootViewController:rootViewController.presentedViewController];
    }
    
    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)rootViewController;
        return [self topViewControllerWithRootViewController:navigationController.visibleViewController];
    }
    
    if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)rootViewController;
        return [self topViewControllerWithRootViewController:tabBarController.selectedViewController];
    }
    
    return rootViewController;
}
#endif

/**
 * Submit a persisted crash report.
 * On success, the crash files are deleted and remaining crashes are sent SILENTLY (no dialog).
 * On failure, the crash files are kept for retry on next app launch.
 */
- (void)submitPersistedCrashReportWithFilename:(NSString *)crashFilename
                               crashReportText:(NSString *)crashReportText
                                      metadata:(NSDictionary *)persistedMetadata
                                      userName:(NSString *)userName
                                     userEmail:(NSString *)userEmail
                                      comments:(NSString *)comments
{
    // Notify delegate (wrapped to prevent crashes)
    @try {
        if ([self.delegate respondsToSelector:@selector(bugSplatWillSendCrashReport:)]) {
            [self.delegate bugSplatWillSendCrashReport:self];
        }
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in bugSplatWillSendCrashReport delegate: %@ - %@", exception.name, exception.reason);
    }
    
    // Load attachments from disk for this crash
    NSArray<BugSplatAttachment *> *attachments = [self loadPersistedAttachmentsForCrashFilename:crashFilename];
    
    // Build upload metadata
    BugSplatCrashMetadata *uploadMetadata = [[BugSplatCrashMetadata alloc] init];
    uploadMetadata.userName = userName;
    uploadMetadata.userEmail = userEmail;
    uploadMetadata.userDescription = comments;
    
    // Use attributes from persisted metadata if current session attributes are nil
    if (self.attributes) {
        uploadMetadata.attributes = self.attributes;
    } else {
        uploadMetadata.attributes = persistedMetadata[kBugSplatMetaKeyAttributes];
    }
    
    uploadMetadata.applicationLog = persistedMetadata[kBugSplatMetaKeyApplicationLog];
    uploadMetadata.applicationKey = persistedMetadata[kBugSplatMetaKeyApplicationKey];
    
    // Convert text report to data for upload
    NSData *textCrashData = [crashReportText dataUsingEncoding:NSUTF8StringEncoding];
    if (!textCrashData) {
        NSLog(@"BugSplat: Failed to encode crash report text");
        self.sendingInProgress = NO;
        return;
    }
    
    NSLog(@"BugSplat: Uploading crash report %@...", crashFilename);
    
    // Upload (NSURLSession handles this on a background thread)
    [self.uploadService uploadCrashReport:textCrashData
                            crashFilename:@"crash.crashlog"
                              attachments:attachments
                                 metadata:uploadMetadata
                               completion:^(BOOL success, NSError *error) {
        // Completion is called on main queue
        if (success) {
            NSLog(@"BugSplat: Crash report %@ uploaded successfully", crashFilename);
            
            // Only cleanup crash files after SUCCESSFUL upload
            self.attributes = nil;
            [self cleanupCrashReportWithFilename:crashFilename];
            
            // Notify delegate
            @try {
                if ([self.delegate respondsToSelector:@selector(bugSplatDidFinishSendingCrashReport:)]) {
                    [self.delegate bugSplatDidFinishSendingCrashReport:self];
                }
            } @catch (NSException *exception) {
                NSLog(@"BugSplat: Exception in bugSplatDidFinishSendingCrashReport delegate: %@ - %@", exception.name, exception.reason);
            }
            
            self.sendingInProgress = NO;
            
            // Process any remaining pending crash reports SILENTLY (no dialog)
            // This matches HockeyApp behavior: show dialog only for first crash,
            // then send remaining crashes silently after user approves.
            // Wait 1 second between uploads to avoid throttling by the server.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self processPendingCrashReportsShowingDialog:NO];
            });
            
        } else {
            // IMPORTANT: On failure, DO NOT delete crash files - they will be retried on next app launch
            NSLog(@"BugSplat: Failed to upload crash report %@: %@ (will retry on next launch)", crashFilename, error);
            
            // Notify delegate
            @try {
                if ([self.delegate respondsToSelector:@selector(bugSplat:didFailWithError:)]) {
                    [self.delegate bugSplat:self didFailWithError:error];
                }
            } @catch (NSException *exception) {
                NSLog(@"BugSplat: Exception in bugSplat:didFailWithError: delegate: %@ - %@", exception.name, exception.reason);
            }
            
            self.sendingInProgress = NO;
            
            // Note: We do NOT process remaining crash reports on failure
            // They will all be retried on next app launch when network may be available
        }
    }];
}

#pragma mark - Properties

- (NSBundle *)bundle
{
    return [NSBundle mainBundle];
}

- (NSString *)bugSplatDatabase
{
    NSString *plistValue = (NSString *)[self.bundle objectForInfoDictionaryKey:kBugSplatDatabase];
    if (plistValue) {
        return [plistValue copy];
    }
    return _bugSplatDatabase;
}

- (void)setBugSplatDatabase:(NSString *)bugSplatDatabase
{
    if (self.bugSplatDatabase) {
        return; // Don't change if already set
    }
    if (bugSplatDatabase && !self.isStartInvoked) {
        _bugSplatDatabase = [bugSplatDatabase copy];
    }
}

- (NSString *)applicationName
{
    return _applicationName;
}

- (void)setApplicationName:(NSString *)applicationName
{
    if (!self.isStartInvoked) {
        _applicationName = [applicationName copy];
    }
}

- (NSString *)applicationVersion
{
    return _applicationVersion;
}

- (void)setApplicationVersion:(NSString *)applicationVersion
{
    if (!self.isStartInvoked) {
        _applicationVersion = [applicationVersion copy];
    }
}

- (NSString *)resolvedApplicationName
{
    if (_applicationName) {
        return _applicationName;
    }
    NSString *displayName = [self.bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (displayName) {
        return displayName;
    }
    NSString *bundleName = [self.bundle objectForInfoDictionaryKey:@"CFBundleName"];
    if (bundleName) {
        return bundleName;
    }
    return @"Unknown Application";
}

- (NSString *)resolvedApplicationVersion
{
    if (_applicationVersion) {
        return _applicationVersion;
    }
    NSString *version = [self.bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (version) {
        return version;
    }
    return @"1.0";
}

- (NSString *)userID
{
    return [NSUserDefaults.standardUserDefaults stringForKey:kBugSplatUserDefaultsUserID];
}

- (void)setUserID:(NSString *)userID
{
    [NSUserDefaults.standardUserDefaults setObject:userID forKey:kBugSplatUserDefaultsUserID];
}

- (NSString *)userName
{
    return [NSUserDefaults.standardUserDefaults stringForKey:kBugSplatUserDefaultsUserName];
}

- (void)setUserName:(NSString *)userName
{
    [NSUserDefaults.standardUserDefaults setObject:userName forKey:kBugSplatUserDefaultsUserName];
}

- (NSString *)userEmail
{
    return [NSUserDefaults.standardUserDefaults stringForKey:kBugSplatUserDefaultsUserEmail];
}

- (void)setUserEmail:(NSString *)userEmail
{
    [NSUserDefaults.standardUserDefaults setObject:userEmail forKey:kBugSplatUserDefaultsUserEmail];
}

#pragma mark - Attributes

- (BOOL)setValue:(nullable NSString *)value forAttribute:(NSString *)attribute
{
    if (!attribute || attribute.length == 0) {
        return NO;
    }
    
    NSMutableDictionary<NSString *, NSString *> *mutableAttributes;
    NSDictionary<NSString *, NSString *> *persistedAttributes = [NSUserDefaults.standardUserDefaults dictionaryForKey:kBugSplatUserDefaultsAttributes];
    
    if (persistedAttributes == nil && value == nil) {
        return NO;
    }
    
    if (persistedAttributes) {
        mutableAttributes = [[NSMutableDictionary alloc] initWithDictionary:persistedAttributes];
    } else {
        mutableAttributes = [NSMutableDictionary dictionary];
    }

    NSLog(@"BugSplat [setValue:%@ forKey:%@]", value, attribute);

    if (value) {
        [mutableAttributes setValue:value forKey:attribute];
    } else {
        [mutableAttributes removeObjectForKey:attribute];
    }
    
    [NSUserDefaults.standardUserDefaults setValue:mutableAttributes forKey:kBugSplatUserDefaultsAttributes];
    
    return YES;
}

#pragma mark - Crash Report Persistence

- (NSString *)crashesDirectoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *appSupportDir = paths.firstObject;
    NSString *crashesDir = [appSupportDir stringByAppendingPathComponent:@"BugSplat/Crashes"];
    
    if (![fileManager fileExistsAtPath:crashesDir]) {
        NSError *error = nil;
        [fileManager createDirectoryAtPath:crashesDir withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"BugSplat: Failed to create crashes directory: %@", error);
            return nil;
        }
    }
    
    return crashesDir;
}

/**
 * Persist attachments to disk with a prefix that associates them with a specific crash.
 */
- (void)persistAttachments:(NSArray<BugSplatAttachment *> *)attachments forCrashFilename:(NSString *)crashFilename
{
    if (!attachments || attachments.count == 0 || !crashFilename) {
        return;
    }
    
    NSString *crashesDir = [self crashesDirectoryPath];
    if (!crashesDir) {
        return;
    }
    
    for (NSUInteger i = 0; i < attachments.count; i++) {
        BugSplatAttachment *attachment = attachments[i];
        @try {
            if (!attachment) {
                continue;
            }
            
            // Use crash filename as prefix so attachments are associated with their crash
            NSString *filename = [NSString stringWithFormat:@"%@-%lu.%@", 
                                  crashFilename,
                                  (unsigned long)i,
                                  kBugSplatAttachmentFileExtension];
            NSString *filePath = [crashesDir stringByAppendingPathComponent:filename];
            
            NSError *error = nil;
            NSData *archiveData = [NSKeyedArchiver archivedDataWithRootObject:attachment 
                                                        requiringSecureCoding:YES 
                                                                        error:&error];
            if (archiveData && !error) {
                [archiveData writeToFile:filePath atomically:YES];
                NSLog(@"BugSplat: Persisted attachment to %@", filename);
            } else {
                NSLog(@"BugSplat: Failed to archive attachment: %@", error);
            }
        } @catch (NSException *exception) {
            NSLog(@"BugSplat: Exception persisting attachment: %@ - %@", exception.name, exception.reason);
        }
    }
}

/**
 * Load persisted attachments for a specific crash.
 */
- (NSArray<BugSplatAttachment *> *)loadPersistedAttachmentsForCrashFilename:(NSString *)crashFilename
{
    if (!crashFilename) {
        return @[];
    }
    
    NSString *crashesDir = [self crashesDirectoryPath];
    if (!crashesDir) {
        return @[];
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = nil;
    
    @try {
        files = [fileManager contentsOfDirectoryAtPath:crashesDir error:&error];
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception listing crashes directory: %@ - %@", exception.name, exception.reason);
        return @[];
    }
    
    if (error || !files) {
        return @[];
    }
    
    NSMutableArray<BugSplatAttachment *> *attachments = [NSMutableArray array];
    NSString *attachmentPrefix = [NSString stringWithFormat:@"%@-", crashFilename];
    NSString *attachmentSuffix = [NSString stringWithFormat:@".%@", kBugSplatAttachmentFileExtension];
    
    for (NSString *filename in files) {
        @try {
            // Only load attachments that belong to this crash
            if (![filename hasPrefix:attachmentPrefix] || ![filename hasSuffix:attachmentSuffix]) {
                continue;
            }
            
            NSString *filePath = [crashesDir stringByAppendingPathComponent:filename];
            NSData *data = [NSData dataWithContentsOfFile:filePath];
            if (!data) {
                continue;
            }
            
            NSError *unarchiveError = nil;
            BugSplatAttachment *attachment = [NSKeyedUnarchiver unarchivedObjectOfClass:[BugSplatAttachment class]
                                                                               fromData:data
                                                                                  error:&unarchiveError];
            if (attachment && !unarchiveError) {
                [attachments addObject:attachment];
                NSLog(@"BugSplat: Loaded persisted attachment from %@", filename);
            } else {
                NSLog(@"BugSplat: Failed to unarchive attachment: %@", unarchiveError);
            }
        } @catch (NSException *exception) {
            NSLog(@"BugSplat: Exception loading persisted attachment %@: %@ - %@", filename, exception.name, exception.reason);
        }
    }
    
    return attachments;
}

/**
 * Cleanup all files associated with a specific crash report.
 * This includes the .crash file, .meta file, and all .data attachment files.
 */
- (void)cleanupCrashReportWithFilename:(NSString *)crashFilename
{
    if (!crashFilename) {
        return;
    }
    
    @try {
        NSString *crashesDir = [self crashesDirectoryPath];
        if (!crashesDir) {
            return;
        }
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error = nil;
        
        // Delete crash file
        NSString *crashFilePath = [[crashesDir stringByAppendingPathComponent:crashFilename] 
                                   stringByAppendingPathExtension:kBugSplatCrashFileExtension];
        if ([fileManager fileExistsAtPath:crashFilePath]) {
            [fileManager removeItemAtPath:crashFilePath error:&error];
            NSLog(@"BugSplat: Cleaned up crash file %@.%@", crashFilename, kBugSplatCrashFileExtension);
        }
        
        // Delete meta file
        NSString *metaFilePath = [[crashesDir stringByAppendingPathComponent:crashFilename] 
                                  stringByAppendingPathExtension:kBugSplatMetaFileExtension];
        if ([fileManager fileExistsAtPath:metaFilePath]) {
            [fileManager removeItemAtPath:metaFilePath error:nil];
            NSLog(@"BugSplat: Cleaned up meta file %@.%@", crashFilename, kBugSplatMetaFileExtension);
        }
        
        // Delete all attachment files for this crash
        NSArray *files = [fileManager contentsOfDirectoryAtPath:crashesDir error:nil];
        NSString *attachmentPrefix = [NSString stringWithFormat:@"%@-", crashFilename];
        NSString *attachmentSuffix = [NSString stringWithFormat:@".%@", kBugSplatAttachmentFileExtension];
        
        for (NSString *filename in files) {
            if ([filename hasPrefix:attachmentPrefix] && [filename hasSuffix:attachmentSuffix]) {
                NSString *filePath = [crashesDir stringByAppendingPathComponent:filename];
                [fileManager removeItemAtPath:filePath error:nil];
                NSLog(@"BugSplat: Cleaned up attachment file %@", filename);
            }
        }
        
        NSLog(@"BugSplat: Cleaned up crash report %@", crashFilename);
        
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in cleanupCrashReportWithFilename: %@ - %@", exception.name, exception.reason);
    }
}

/**
 * Cleanup ALL pending crash reports.
 * Called when user cancels the crash report dialog - discards all pending crashes.
 */
- (void)cleanupAllPendingCrashReports
{
    @try {
        NSArray<NSString *> *pendingCrashFiles = [self getPendingCrashFiles];
        NSLog(@"BugSplat: Cleaning up all %lu pending crash report(s)", (unsigned long)pendingCrashFiles.count);
        
        for (NSString *crashFilename in pendingCrashFiles) {
            [self cleanupCrashReportWithFilename:crashFilename];
        }
        
        NSLog(@"BugSplat: All pending crash reports cleaned up");
        
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in cleanupAllPendingCrashReports: %@ - %@", exception.name, exception.reason);
    }
}

@end
