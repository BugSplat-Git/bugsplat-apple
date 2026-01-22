//
//  BugSplat.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <BugSplatMac/BugSplat.h>
#else
#import <BugSplat/BugSplat.h>
#endif

#import <CrashReporter/CrashReporter.h>
#import "BugSplatUtilities.h"
#import "BugSplatUploadService.h"
#import "BugSplatZipHelper.h"
#import "BugSplatTestSupport.h"
#import "BugSplat+Testing.h"

#if TARGET_OS_OSX
#import "BugSplatCrashReportWindow.h"
#else
#import <UIKit/UIKit.h>
#endif

// NSUserDefaults keys - only for dialog pre-population and user preferences
NSString *const kBugSplatUserDefaultsUserName = @"com.bugsplat.userName";
NSString *const kBugSplatUserDefaultsUserEmail = @"com.bugsplat.userEmail";
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
static NSString *const kBugSplatMetaKeyTimestamp = @"timestamp";
static NSString *const kBugSplatMetaKeyUserSubmitted = @"userSubmitted";
// Crash-time context (may differ from current app if updated before upload)
static NSString *const kBugSplatMetaKeyDatabase = @"database";
static NSString *const kBugSplatMetaKeyApplicationName = @"applicationName";
static NSString *const kBugSplatMetaKeyApplicationVersion = @"applicationVersion";
static NSString *const kBugSplatMetaKeyAppKey = @"appKey";
static NSString *const kBugSplatMetaKeyNotes = @"notes";

@interface BugSplat ()

@property (atomic, assign) BOOL isStartInvoked;
@property (atomic, assign) BOOL sendingInProgress;
@property (nonatomic, nullable) NSDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, strong) id<BugSplatCrashReporterProtocol> crashReporterInternal;
@property (nonatomic, strong, nullable) id<BugSplatCrashStorageProtocol> crashStorageInternal;
@property (nonatomic, strong, nullable) id<BugSplatUserDefaultsProtocol> userDefaultsInternal;
@property (nonatomic, strong, nullable) id<BugSplatBundleProtocol> bundleInternal;
@property (nonatomic, strong, nullable) BugSplatUploadService *uploadService;
@property (nonatomic, copy, nullable) NSString *currentCrashFilename;
@property (nonatomic, assign) BOOL isTestInstance;

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
    });
    
    return sharedInstance;
}

- (instancetype)init
{
    if (self = [super init]) {
        self.isStartInvoked = NO;
        self.sendingInProgress = NO;
        self.currentCrashFilename = nil;
        self.isTestInstance = NO;

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
        
        _crashReporterInternal = (id<BugSplatCrashReporterProtocol>)[[PLCrashReporter alloc] initWithConfiguration:config];
        
        // Use real defaults by default
        _userDefaultsInternal = (id<BugSplatUserDefaultsProtocol>)[NSUserDefaults standardUserDefaults];
        _bundleInternal = (id<BugSplatBundleProtocol>)[NSBundle mainBundle];

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

- (instancetype)initForTestingWithCrashReporter:(id<BugSplatCrashReporterProtocol>)crashReporter
                                   crashStorage:(id<BugSplatCrashStorageProtocol>)crashStorage
                                   userDefaults:(id<BugSplatUserDefaultsProtocol>)userDefaults
                                         bundle:(id<BugSplatBundleProtocol>)bundle
{
    if (self = [super init]) {
        self.isStartInvoked = NO;
        self.sendingInProgress = NO;
        self.currentCrashFilename = nil;
        self.isTestInstance = YES;
        
        _crashReporterInternal = crashReporter;
        _crashStorageInternal = crashStorage;
        _userDefaultsInternal = userDefaults;
        _bundleInternal = bundle;
        
#if TARGET_OS_OSX
        _autoSubmitCrashReport = NO;
        _askUserDetails = YES;
        _expirationTimeInterval = -1;
#else
        _autoSubmitCrashReport = YES;
#endif
    }
    return self;
}

// Convenience accessor that returns the crashReporter as PLCrashReporter for internal use
- (PLCrashReporter *)crashReporter
{
    return (PLCrashReporter *)self.crashReporterInternal;
}

- (void)start
{
    NSLog(@"BugSplat start...");
    
    // Debug: Check what bundle and info dictionary we're reading from
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSLog(@"BugSplat: mainBundle = %@", mainBundle);
    NSLog(@"BugSplat: bundleIdentifier = %@", mainBundle.bundleIdentifier);
    NSLog(@"BugSplat: infoDictionary = %@", mainBundle.infoDictionary);
    NSLog(@"BugSplat: BugSplatDatabase from infoDictionary = %@", [mainBundle objectForInfoDictionaryKey:@"BugSplatDatabase"]);
    NSLog(@"BugSplat: self.bundleProtocol = %@", self.bundleProtocol);
    NSLog(@"BugSplat: self.bugSplatDatabase = %@", self.bugSplatDatabase);

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
    // The crash-time metadata is embedded in the crash report via customData
    if ([self.crashReporter hasPendingCrashReport]) {
        [self handleNewCrashFromPLCrashReporter];
    }
    
    // Then, process any pending crash reports from our crashes directory
    // This includes both new crashes and previously failed uploads
    [self processPendingCrashReports];
    
    // Set crash-time metadata on PLCrashReporter BEFORE enabling it
    // If a crash occurs, this metadata will be saved WITH the crash report
    [self updateCrashReporterCustomData];
    
    // Enable crash reporter for this session
    NSError *error = nil;
    if (![self.crashReporter enableCrashReporterAndReturnError:&error]) {
        NSLog(@"BugSplat: Failed to enable crash reporter: %@", error);
        return;
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
    
    // Build and persist metadata for THIS CRASH
    // The crash-time properties are embedded in the crash report via PLCrashReporter's customData
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    
    // Use the actual crash time from the crash report, fall back to current time if unavailable
    NSDate *crashTimestamp = crashReport.systemInfo.timestamp ?: [NSDate date];
    
    // Store as ISO 8601 string for reliable persistence and API compatibility
    NSISO8601DateFormatter *isoFormatter = [[NSISO8601DateFormatter alloc] init];
    isoFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    NSString *crashTimeISO = [isoFormatter stringFromDate:crashTimestamp];
    metadata[kBugSplatMetaKeyTimestamp] = crashTimeISO;
    
    // Extract crash-time properties from PLCrashReporter's customData
    // This data was set BEFORE the crash occurred and is bundled WITH the crash
    NSDictionary *crashTimeProperties = nil;
    if (crashReport.customData) {
        @try {
            crashTimeProperties = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSDictionary class]
                                                                    fromData:crashReport.customData
                                                                       error:nil];
        } @catch (NSException *exception) {
            NSLog(@"BugSplat: Exception deserializing customData: %@ - %@", exception.name, exception.reason);
        }
    }
    
    if (crashTimeProperties) {
        // Use the properties that were set when the crash occurred
        if (crashTimeProperties[kBugSplatMetaKeyDatabase]) {
            metadata[kBugSplatMetaKeyDatabase] = crashTimeProperties[kBugSplatMetaKeyDatabase];
        }
        if (crashTimeProperties[kBugSplatMetaKeyApplicationName]) {
            metadata[kBugSplatMetaKeyApplicationName] = crashTimeProperties[kBugSplatMetaKeyApplicationName];
        }
        if (crashTimeProperties[kBugSplatMetaKeyApplicationVersion]) {
            metadata[kBugSplatMetaKeyApplicationVersion] = crashTimeProperties[kBugSplatMetaKeyApplicationVersion];
        }
        if (crashTimeProperties[kBugSplatMetaKeyUserName]) {
            metadata[kBugSplatMetaKeyUserName] = crashTimeProperties[kBugSplatMetaKeyUserName];
        }
        if (crashTimeProperties[kBugSplatMetaKeyUserEmail]) {
            metadata[kBugSplatMetaKeyUserEmail] = crashTimeProperties[kBugSplatMetaKeyUserEmail];
        }
        if (crashTimeProperties[kBugSplatMetaKeyAppKey]) {
            metadata[kBugSplatMetaKeyAppKey] = crashTimeProperties[kBugSplatMetaKeyAppKey];
        }
        if (crashTimeProperties[kBugSplatMetaKeyNotes]) {
            metadata[kBugSplatMetaKeyNotes] = crashTimeProperties[kBugSplatMetaKeyNotes];
        }
        if (crashTimeProperties[kBugSplatMetaKeyAttributes]) {
            metadata[kBugSplatMetaKeyAttributes] = crashTimeProperties[kBugSplatMetaKeyAttributes];
        }
        
        NSLog(@"BugSplat: Extracted crash-time metadata from crash report - database: %@, app: %@ %@",
              metadata[kBugSplatMetaKeyDatabase],
              metadata[kBugSplatMetaKeyApplicationName],
              metadata[kBugSplatMetaKeyApplicationVersion]);
    } else {
        // No customData in crash report - this is an old crash or customData wasn't set
        // Fall back to current values
        NSLog(@"BugSplat: No crash-time metadata in crash report, using current values");
        metadata[kBugSplatMetaKeyDatabase] = self.bugSplatDatabase;
        metadata[kBugSplatMetaKeyApplicationName] = self.resolvedApplicationName;
        metadata[kBugSplatMetaKeyApplicationVersion] = self.resolvedApplicationVersion;
        if (self.userName) metadata[kBugSplatMetaKeyUserName] = self.userName;
        if (self.userEmail) metadata[kBugSplatMetaKeyUserEmail] = self.userEmail;
        if (self.appKey) metadata[kBugSplatMetaKeyAppKey] = self.appKey;
        if (self.notes) metadata[kBugSplatMetaKeyNotes] = self.notes;
        if (self.attributes) metadata[kBugSplatMetaKeyAttributes] = self.attributes;
    }
    
    // Get application log from delegate
    @try {
        if ([self.delegate respondsToSelector:@selector(applicationLogForBugSplat:)]) {
            NSString *appLog = [self.delegate applicationLogForBugSplat:self];
            if (appLog) metadata[kBugSplatMetaKeyApplicationLog] = appLog;
        }
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception in applicationLogForBugSplat delegate: %@ - %@", exception.name, exception.reason);
    }
    
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
 * Processes newest-first so:
 * - The most recent crash (likely needing a dialog) is shown to the user first
 * - Older crashes (already submitted, retrying) are sent silently after
 */
- (void)processPendingCrashReports
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
    
    // Process the newest crash first (last in the sorted array)
    // When crashes stack up we want to show the dialog for the newest crash immediately instead of waiting for older crashes to be processed.
    NSString *crashFilename = pendingCrashFiles.lastObject;
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
        [self processPendingCrashReports];
        return;
    }
    
    NSString *crashReportText = [[NSString alloc] initWithData:crashData encoding:NSUTF8StringEncoding];
    if (!crashReportText) {
        NSLog(@"BugSplat: Failed to decode crash report text, cleaning up");
        [self cleanupCrashReportWithFilename:crashFilename];
        self.sendingInProgress = NO;
        [self processPendingCrashReports];
        return;
    }
    
    // Load metadata
    NSString *metaFilePath = [[crashesDir stringByAppendingPathComponent:crashFilename] 
                              stringByAppendingPathExtension:kBugSplatMetaFileExtension];
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metaFilePath];
    
    // Determine if we should send silently or show a dialog
    BOOL sendSilently = [self shouldSendCrashSilently:metadata];
    
    if (sendSilently) {
        NSLog(@"BugSplat: Sending crash %@ silently", crashFilename);
        [self submitCrashSilentlyWithFilename:crashFilename
                              crashReportText:crashReportText
                                     metadata:metadata];
    } else {
#if TARGET_OS_OSX
        [self showCrashReportDialogForFilename:crashFilename 
                               crashReportText:crashReportText 
                                      metadata:metadata];
#else
        [self showCrashReportAlertForFilename:crashFilename 
                              crashReportText:crashReportText 
                                     metadata:metadata];
#endif
    }
}

/**
 * Determine if a crash should be sent silently (without showing a dialog).
 */
- (BOOL)shouldSendCrashSilently:(NSDictionary *)metadata
{
    // User already submitted this crash (retrying after failed upload)
    if ([metadata[kBugSplatMetaKeyUserSubmitted] boolValue]) {
        return YES;
    }
    
    // Auto-submit is enabled
    if (self.autoSubmitCrashReport) {
        return YES;
    }
    
#if TARGET_OS_OSX
    // Crash report has expired
    @try {
        NSNumber *timestamp = metadata[kBugSplatMetaKeyTimestamp];
        if (self.expirationTimeInterval > 0 && timestamp) {
            NSTimeInterval timeSinceCrash = [[NSDate date] timeIntervalSince1970] - timestamp.doubleValue;
            if (timeSinceCrash > self.expirationTimeInterval) {
                NSLog(@"BugSplat: Crash report expired (%.0f seconds old)", timeSinceCrash);
                return YES;
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"BugSplat: Exception checking crash report expiration: %@ - %@", exception.name, exception.reason);
    }
#else
    // iOS: User chose "Always Send"
    if ([self.userDefaultsInternal boolForKey:kBugSplatUserDefaultsAlwaysSend]) {
        return YES;
    }
#endif
    
    return NO;
}

/**
 * Submit a crash report silently (without user interaction).
 */
- (void)submitCrashSilentlyWithFilename:(NSString *)crashFilename
                        crashReportText:(NSString *)crashReportText
                               metadata:(NSDictionary *)metadata
{
    // Use ONLY values from the per-crash metadata - no fallbacks to current values
    [self submitPersistedCrashReportWithFilename:crashFilename 
                                 crashReportText:crashReportText 
                                        metadata:metadata 
                                        userName:metadata[kBugSplatMetaKeyUserName]
                                       userEmail:metadata[kBugSplatMetaKeyUserEmail]
                                        comments:metadata[kBugSplatMetaKeyComments]
                                   isInteractive:NO];
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
                                                            comments:comments
                                                       isInteractive:YES];
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
            // Fall back to auto-submit if dialog fails - use metadata values only
            [self submitPersistedCrashReportWithFilename:crashFilename
                                         crashReportText:crashReportText
                                                metadata:metadata
                                                userName:metadata[kBugSplatMetaKeyUserName]
                                               userEmail:metadata[kBugSplatMetaKeyUserEmail]
                                                comments:metadata[kBugSplatMetaKeyComments]
                                           isInteractive:NO];
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
                                                    userName:metadata[kBugSplatMetaKeyUserName]
                                                   userEmail:metadata[kBugSplatMetaKeyUserEmail]
                                                    comments:metadata[kBugSplatMetaKeyComments]
                                               isInteractive:YES];
            }];
            [alert addAction:sendAction];
            
            // "Always Send" action
            UIAlertAction *alwaysSendAction = [UIAlertAction actionWithTitle:@"Always Send"
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^(UIAlertAction *action) {
                // Save the "always send" preference
                [self.userDefaultsInternal setBool:YES forKey:kBugSplatUserDefaultsAlwaysSend];
                
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
                                                    userName:metadata[kBugSplatMetaKeyUserName]
                                                   userEmail:metadata[kBugSplatMetaKeyUserEmail]
                                                    comments:metadata[kBugSplatMetaKeyComments]
                                               isInteractive:YES];
            }];
            [alert addAction:alwaysSendAction];
            
            // Find the top-most view controller to present the alert
            UIViewController *presentingViewController = [self topMostViewController];
            if (presentingViewController) {
                [presentingViewController presentViewController:alert animated:YES completion:nil];
            } else {
                NSLog(@"BugSplat: Could not find view controller to present crash report alert, auto-submitting...");
                // Fall back to auto-submit if no view controller available - use metadata values only
                [self submitPersistedCrashReportWithFilename:crashFilename
                                             crashReportText:crashReportText
                                                    metadata:metadata
                                                    userName:metadata[kBugSplatMetaKeyUserName]
                                                   userEmail:metadata[kBugSplatMetaKeyUserEmail]
                                                    comments:metadata[kBugSplatMetaKeyComments]
                                               isInteractive:NO];
            }
        } @catch (NSException *exception) {
            NSLog(@"BugSplat: Exception showing crash report alert: %@ - %@", exception.name, exception.reason);
            // Fall back to auto-submit if alert fails - use metadata values only
            [self submitPersistedCrashReportWithFilename:crashFilename
                                         crashReportText:crashReportText
                                                metadata:metadata
                                                userName:metadata[kBugSplatMetaKeyUserName]
                                               userEmail:metadata[kBugSplatMetaKeyUserEmail]
                                                comments:metadata[kBugSplatMetaKeyComments]
                                           isInteractive:NO];
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
 *
 * @param isInteractive YES if this crash was submitted via user interaction (dialog),
 *                      NO if sent silently. On macOS, interactive submissions will open
 *                      the infoUrl in the browser if one is returned.
 */
- (void)submitPersistedCrashReportWithFilename:(NSString *)crashFilename
                               crashReportText:(NSString *)crashReportText
                                      metadata:(NSDictionary *)persistedMetadata
                                      userName:(NSString *)userName
                                     userEmail:(NSString *)userEmail
                                      comments:(NSString *)comments
                                 isInteractive:(BOOL)isInteractive
{
    // Mark this crash as user-submitted and persist any comments
    // This ensures: 1) comments survive failed uploads, 2) we know to retry silently
    [self markCrashAsSubmittedWithComments:comments userName:userName userEmail:userEmail forCrashFilename:crashFilename];
    
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
    
    // Build upload metadata from the per-crash metadata ONLY
    // The metadata is bundled with this crash and contains all values from when the crash occurred
    // Do NOT fall back to current BugSplat values - this crash may be uploaded many launches later
    BugSplatCrashMetadata *uploadMetadata = [[BugSplatCrashMetadata alloc] init];
    
    // All values come from the per-crash metadata
    uploadMetadata.database = persistedMetadata[kBugSplatMetaKeyDatabase];
    uploadMetadata.applicationName = persistedMetadata[kBugSplatMetaKeyApplicationName];
    uploadMetadata.applicationVersion = persistedMetadata[kBugSplatMetaKeyApplicationVersion];
    uploadMetadata.userName = userName;
    uploadMetadata.userEmail = userEmail;
    uploadMetadata.userDescription = comments;
    uploadMetadata.crashTime = persistedMetadata[kBugSplatMetaKeyTimestamp];
    uploadMetadata.attributes = persistedMetadata[kBugSplatMetaKeyAttributes];
    uploadMetadata.applicationLog = persistedMetadata[kBugSplatMetaKeyApplicationLog];
    uploadMetadata.notes = persistedMetadata[kBugSplatMetaKeyNotes];
    uploadMetadata.applicationKey = persistedMetadata[kBugSplatMetaKeyAppKey];
    
    // Convert text report to data for upload
    NSData *textCrashData = [crashReportText dataUsingEncoding:NSUTF8StringEncoding];
    if (!textCrashData) {
        NSLog(@"BugSplat: Failed to encode crash report text");
        self.sendingInProgress = NO;
        return;
    }
    
    NSLog(@"BugSplat: Uploading crash report %@ (app: %@ %@, database: %@)...", 
          crashFilename, 
          uploadMetadata.applicationName, 
          uploadMetadata.applicationVersion, 
          uploadMetadata.database);
    
    // Upload (NSURLSession handles this on a background thread)
    // Use weak/strong self pattern to avoid retain cycles
    __weak typeof(self) weakSelf = self;
    [self.uploadService uploadCrashReport:textCrashData
                            crashFilename:@"crash.crashlog"
                              attachments:attachments
                                 metadata:uploadMetadata
                               completion:^(BOOL success, NSError *error, NSString *infoUrl) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        // Completion is called on main queue
        if (success) {
            NSLog(@"BugSplat: Crash report %@ uploaded successfully", crashFilename);
            
            // Only cleanup crash files after SUCCESSFUL upload
            strongSelf.attributes = nil;
            [strongSelf cleanupCrashReportWithFilename:crashFilename];
            
#if TARGET_OS_OSX
            // Open infoUrl in browser for interactive submissions on macOS
            if (isInteractive && infoUrl.length > 0) {
                NSURL *url = [NSURL URLWithString:infoUrl];
                if (url) {
                    NSLog(@"BugSplat: Opening crash report URL in browser: %@", infoUrl);
                    [[NSWorkspace sharedWorkspace] openURL:url];
                }
            }
#endif
            
            // Notify delegate
            @try {
                if ([strongSelf.delegate respondsToSelector:@selector(bugSplatDidFinishSendingCrashReport:)]) {
                    [strongSelf.delegate bugSplatDidFinishSendingCrashReport:strongSelf];
                }
            } @catch (NSException *exception) {
                NSLog(@"BugSplat: Exception in bugSplatDidFinishSendingCrashReport delegate: %@ - %@", exception.name, exception.reason);
            }
            
            strongSelf.sendingInProgress = NO;
            
            // Process any remaining pending crash reports.
            // Wait 1 second between uploads to avoid throttling by the server.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [strongSelf processPendingCrashReports];
            });
            
        } else {
            // IMPORTANT: On failure, DO NOT delete crash files - they will be retried on next app launch
            NSLog(@"BugSplat: Failed to upload crash report %@: %@ (will retry on next launch)", crashFilename, error);
            
            // Notify delegate
            @try {
                if ([strongSelf.delegate respondsToSelector:@selector(bugSplat:didFailWithError:)]) {
                    [strongSelf.delegate bugSplat:strongSelf didFailWithError:error];
                }
            } @catch (NSException *exception) {
                NSLog(@"BugSplat: Exception in bugSplat:didFailWithError: delegate: %@ - %@", exception.name, exception.reason);
            }
            
            strongSelf.sendingInProgress = NO;
            
            // Note: We do NOT process remaining crash reports on failure
            // They will all be retried on next app launch when network may be available
        }
    }];
}

#pragma mark - Properties

- (NSBundle *)bundle
{
    if (self.bundleInternal && [self.bundleInternal isKindOfClass:[NSBundle class]]) {
        return (NSBundle *)self.bundleInternal;
    }
    return [NSBundle mainBundle];
}

- (id<BugSplatBundleProtocol>)bundleProtocol
{
    return self.bundleInternal ?: (id<BugSplatBundleProtocol>)[NSBundle mainBundle];
}

- (NSString *)bugSplatDatabase
{
    // Programmatic value takes precedence, then fall back to Info.plist
    if (_bugSplatDatabase) {
        return _bugSplatDatabase;
    }
    return (NSString *)[self.bundleProtocol objectForInfoDictionaryKey:kBugSplatDatabase];
}

- (void)setBugSplatDatabase:(NSString *)bugSplatDatabase
{
    _bugSplatDatabase = [bugSplatDatabase copy];
    [self updateCrashReporterCustomData];
}

- (NSString *)applicationName
{
    return _applicationName;
}

- (void)setApplicationName:(NSString *)applicationName
{
    _applicationName = [applicationName copy];
    [self updateCrashReporterCustomData];
}

- (NSString *)applicationVersion
{
    return _applicationVersion;
}

- (void)setApplicationVersion:(NSString *)applicationVersion
{
    _applicationVersion = [applicationVersion copy];
    [self updateCrashReporterCustomData];
}

- (NSString *)resolvedApplicationName
{
    if (_applicationName) {
        return _applicationName;
    }
    NSString *displayName = [self.bundleProtocol objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (displayName) {
        return displayName;
    }
    NSString *bundleName = [self.bundleProtocol objectForInfoDictionaryKey:@"CFBundleName"];
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
    NSString *shortVersion = [self.bundleProtocol objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [self.bundleProtocol objectForInfoDictionaryKey:@"CFBundleVersion"];
    
    if (shortVersion && buildNumber) {
        return [NSString stringWithFormat:@"%@ (%@)", shortVersion, buildNumber];
    }
    if (shortVersion) {
        return shortVersion;
    }
    if (buildNumber) {
        return buildNumber;
    }
    return @"1.0";
}

- (NSString *)userName
{
    return [self.userDefaultsInternal stringForKey:kBugSplatUserDefaultsUserName];
}

- (void)setUserName:(NSString *)userName
{
    [self.userDefaultsInternal setObject:userName forKey:kBugSplatUserDefaultsUserName];
    [self updateCrashReporterCustomData];
}

- (NSString *)userEmail
{
    return [self.userDefaultsInternal stringForKey:kBugSplatUserDefaultsUserEmail];
}

- (void)setUserEmail:(NSString *)userEmail
{
    [self.userDefaultsInternal setObject:userEmail forKey:kBugSplatUserDefaultsUserEmail];
    [self updateCrashReporterCustomData];
}

// appKey and notes use synthesized ivars - setters call updateCrashReporterCustomData

- (void)setAppKey:(NSString *)appKey
{
    _appKey = [appKey copy];
    [self updateCrashReporterCustomData];
}

- (void)setNotes:(NSString *)notes
{
    _notes = [notes copy];
    [self updateCrashReporterCustomData];
}

#pragma mark - Attributes

- (BOOL)setValue:(nullable NSString *)value forAttribute:(NSString *)attribute
{
    if (!attribute || attribute.length == 0) {
        return NO;
    }
    
    if (self.attributes == nil && value == nil) {
        return NO;
    }
    
    NSMutableDictionary<NSString *, NSString *> *mutableAttributes;
    if (self.attributes) {
        mutableAttributes = [[NSMutableDictionary alloc] initWithDictionary:self.attributes];
    } else {
        mutableAttributes = [NSMutableDictionary dictionary];
    }

    NSLog(@"BugSplat [setValue:%@ forKey:%@]", value, attribute);

    if (value) {
        [mutableAttributes setValue:value forKey:attribute];
    } else {
        [mutableAttributes removeObjectForKey:attribute];
    }
    
    self.attributes = mutableAttributes;
    [self updateCrashReporterCustomData];
    
    return YES;
}

#pragma mark - PLCrashReporter Custom Data

/**
 * Update PLCrashReporter's customData with current BugSplat properties.
 * This data is saved WITH the crash report when a crash occurs.
 * When we process the crash, we extract this data to get the crash-time properties.
 *
 * Call this method:
 * - In start(), before enabling the crash reporter
 * - Whenever a property changes that should be associated with crashes
 */
- (void)updateCrashReporterCustomData
{
    NSMutableDictionary *crashMetadata = [NSMutableDictionary dictionary];
    
    // Required properties (always have values - Info.plist or fallbacks)
    crashMetadata[kBugSplatMetaKeyDatabase] = self.bugSplatDatabase;
    crashMetadata[kBugSplatMetaKeyApplicationName] = self.resolvedApplicationName;
    crashMetadata[kBugSplatMetaKeyApplicationVersion] = self.resolvedApplicationVersion;
    
    // Optional properties
    if (self.userName) crashMetadata[kBugSplatMetaKeyUserName] = self.userName;
    if (self.userEmail) crashMetadata[kBugSplatMetaKeyUserEmail] = self.userEmail;
    if (self.appKey) crashMetadata[kBugSplatMetaKeyAppKey] = self.appKey;
    if (self.notes) crashMetadata[kBugSplatMetaKeyNotes] = self.notes;
    
    // Attributes
    if (self.attributes) crashMetadata[kBugSplatMetaKeyAttributes] = self.attributes;
    
    // Serialize and set on PLCrashReporter
    NSError *error = nil;
    NSData *customData = [NSKeyedArchiver archivedDataWithRootObject:crashMetadata
                                               requiringSecureCoding:NO
                                                               error:&error];
    if (customData && !error) {
        self.crashReporter.customData = customData;
        NSLog(@"BugSplat: Set crash-time metadata on PLCrashReporter - database: %@, app: %@ %@",
              crashMetadata[kBugSplatMetaKeyDatabase],
              crashMetadata[kBugSplatMetaKeyApplicationName],
              crashMetadata[kBugSplatMetaKeyApplicationVersion]);
    } else {
        NSLog(@"BugSplat: Failed to serialize crash metadata: %@", error);
    }
}

#pragma mark - Crash Report Persistence

/**
 * Mark a crash as submitted by the user and persist any comments/user info.
 * This ensures:
 * 1. User-entered comments survive failed uploads and app restarts
 * 2. The crash will be retried silently (no dialog) on future launches
 */
- (void)markCrashAsSubmittedWithComments:(NSString *)comments
                                userName:(NSString *)userName
                               userEmail:(NSString *)userEmail
                        forCrashFilename:(NSString *)crashFilename
{
    if (!crashFilename) {
        return;
    }
    
    NSString *crashesDir = [self crashesDirectoryPath];
    if (!crashesDir) {
        return;
    }
    
    NSString *metaFilePath = [[crashesDir stringByAppendingPathComponent:crashFilename] 
                              stringByAppendingPathExtension:kBugSplatMetaFileExtension];
    
    // Load existing metadata or create new dictionary
    NSMutableDictionary *metadata = nil;
    NSDictionary *existingMetadata = [NSDictionary dictionaryWithContentsOfFile:metaFilePath];
    if (existingMetadata) {
        metadata = [existingMetadata mutableCopy];
    } else {
        metadata = [NSMutableDictionary dictionary];
    }
    
    // Mark as user-submitted so we retry silently on future launches
    metadata[kBugSplatMetaKeyUserSubmitted] = @YES;
    NSLog(@"BugSplat: Marked crash %@ as user-submitted", crashFilename);
    
    // Update with new values if provided
    if (comments.length > 0) {
        metadata[kBugSplatMetaKeyComments] = comments;
        NSLog(@"BugSplat: Persisted comments for crash %@", crashFilename);
    }
    if (userName.length > 0) {
        metadata[kBugSplatMetaKeyUserName] = userName;
    }
    if (userEmail.length > 0) {
        metadata[kBugSplatMetaKeyUserEmail] = userEmail;
    }
    
    // Write back to disk
    [metadata writeToFile:metaFilePath atomically:YES];
}

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
        @autoreleasepool {
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
        @autoreleasepool {
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

#pragma mark - Testing Category

@implementation BugSplat (Testing)

+ (instancetype)testInstanceWithCrashReporter:(id<BugSplatCrashReporterProtocol>)crashReporter
                                 crashStorage:(id<BugSplatCrashStorageProtocol>)crashStorage
                                 userDefaults:(id<BugSplatUserDefaultsProtocol>)userDefaults
                                       bundle:(id<BugSplatBundleProtocol>)bundle
{
    return [[BugSplat alloc] initForTestingWithCrashReporter:crashReporter
                                                crashStorage:crashStorage
                                                userDefaults:userDefaults
                                                      bundle:bundle];
}

- (void)setUploadServiceForTesting:(BugSplatUploadService *)uploadService
{
    self.uploadService = uploadService;
}

- (BOOL)isStartInvoked
{
    return _isStartInvoked;
}

- (BOOL)isSendingInProgress
{
    return self.sendingInProgress;
}

- (NSString *)currentCrashFilename
{
    return _currentCrashFilename;
}

- (id<BugSplatCrashReporterProtocol>)crashReporter
{
    return self.crashReporterInternal;
}

- (id<BugSplatCrashStorageProtocol>)crashStorage
{
    return self.crashStorageInternal;
}

@end
