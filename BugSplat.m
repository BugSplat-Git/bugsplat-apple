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
#endif

NSString *const kBugSplatUserDefaultsUserID = @"com.bugsplat.userID";
NSString *const kBugSplatUserDefaultsUserName = @"com.bugsplat.userName";
NSString *const kBugSplatUserDefaultsUserEmail = @"com.bugsplat.userEmail";
NSString *const kBugSplatUserDefaultsAttributes = @"com.bugsplat.attributes";

@interface BugSplat ()

@property (atomic, assign) BOOL isStartInvoked;
@property (nonatomic, nullable) NSDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, strong) PLCrashReporter *crashReporter;
@property (nonatomic, strong, nullable) BugSplatUploadService *uploadService;

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
    
    // Check for pending crash report from previous session
    if ([self.crashReporter hasPendingCrashReport]) {
        [self handlePendingCrashReport];
    }
    
    // Enable crash reporter for this session
    NSError *error = nil;
    if (![self.crashReporter enableCrashReporterAndReturnError:&error]) {
        NSLog(@"BugSplat: Failed to enable crash reporter: %@", error);
    }
    
    self.isStartInvoked = YES;
}

#pragma mark - Crash Report Handling

- (void)handlePendingCrashReport
{
    NSLog(@"BugSplat: Processing pending crash report...");
    
    NSError *error = nil;
    NSData *crashData = [self.crashReporter loadPendingCrashReportDataAndReturnError:&error];
    
    if (!crashData) {
        NSLog(@"BugSplat: Failed to load crash report: %@", error);
        [self.crashReporter purgePendingCrashReport];
        return;
    }
    
    // Parse crash report to get text representation
    PLCrashReport *crashReport = [[PLCrashReport alloc] initWithData:crashData error:&error];
    if (!crashReport) {
        NSLog(@"BugSplat: Failed to parse crash report: %@", error);
        [self.crashReporter purgePendingCrashReport];
        return;
    }
    
    NSString *crashReportText = [PLCrashReportTextFormatter stringValueForCrashReport:crashReport
                                                                       withTextFormat:PLCrashReportTextFormatiOS];
    
    // IMMEDIATELY gather attachments from delegate and persist to disk
    // This captures attachment data early, before app state changes
    NSMutableArray<BugSplatAttachment *> *attachments = [NSMutableArray array];
    
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
    
    // Persist attachments to disk immediately
    if (attachments.count > 0) {
        [self persistAttachments:attachments];
    }
    
    // Check expiration (macOS only)
#if TARGET_OS_OSX
    if (self.expirationTimeInterval > 0 && crashReport.systemInfo.timestamp) {
        NSTimeInterval timeSinceCrash = [[NSDate date] timeIntervalSinceDate:crashReport.systemInfo.timestamp];
        if (timeSinceCrash > self.expirationTimeInterval) {
            NSLog(@"BugSplat: Crash report expired, auto-submitting...");
            [self submitCrashReport:crashData crashReportText:crashReportText userName:self.userName userEmail:self.userEmail comments:nil];
            return;
        }
    }
#endif
    
    // Determine whether to show dialog or auto-submit
    if (self.autoSubmitCrashReport) {
        [self submitCrashReport:crashData crashReportText:crashReportText userName:self.userName userEmail:self.userEmail comments:nil];
    } else {
#if TARGET_OS_OSX
        [self showCrashReportDialogWithData:crashData crashReportText:crashReportText];
#else
        // iOS always auto-submits in this implementation
        [self submitCrashReport:crashData crashReportText:crashReportText userName:self.userName userEmail:self.userEmail comments:nil];
#endif
    }
}

#if TARGET_OS_OSX
- (void)showCrashReportDialogWithData:(NSData *)crashData crashReportText:(NSString *)crashReportText
{
    // Notify delegate
    if ([self.delegate respondsToSelector:@selector(bugSplatWillShowSubmitCrashReportAlert:)]) {
        [self.delegate bugSplatWillShowSubmitCrashReportAlert:self];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
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
            if (action == BugSplatUserActionSend) {
                // Persist user details if enabled
                if (self.persistUserDetails) {
                    if (userName.length > 0) self.userName = userName;
                    if (userEmail.length > 0) self.userEmail = userEmail;
                }
                
                [self submitCrashReport:crashData crashReportText:crashReportText userName:userName userEmail:userEmail comments:comments];
            } else {
                // User cancelled
                if ([self.delegate respondsToSelector:@selector(bugSplatWillCancelSendingCrashReport:)]) {
                    [self.delegate bugSplatWillCancelSendingCrashReport:self];
                }
                // Cleanup persisted attachments and crash report
                [self cleanupPersistedAttachments];
                self.attributes = nil;
                [self.crashReporter purgePendingCrashReport];
            }
            
            self.crashReportWindow = nil;
        };
        
        if (self.presentModally) {
            [self.crashReportWindow showModalWithCompletion:completionHandler];
        } else {
            [self.crashReportWindow showWithCompletion:completionHandler];
        }
    });
}
#endif

- (void)submitCrashReport:(NSData *)crashData
          crashReportText:(NSString *)crashReportText
                 userName:(NSString *)userName
                userEmail:(NSString *)userEmail
                 comments:(NSString *)comments
{
    // Notify delegate
    if ([self.delegate respondsToSelector:@selector(bugSplatWillSendCrashReport:)]) {
        [self.delegate bugSplatWillSendCrashReport:self];
    }
    
    // Load attachments from disk (they were persisted in handlePendingCrashReport)
    NSArray<BugSplatAttachment *> *attachments = [self loadPersistedAttachments];
    
    // Build metadata
    BugSplatCrashMetadata *metadata = [[BugSplatCrashMetadata alloc] init];
    metadata.userName = userName;
    metadata.userEmail = userEmail;
    metadata.userDescription = comments;
    metadata.attributes = self.attributes;
    
    // Get application log from delegate
    if ([self.delegate respondsToSelector:@selector(applicationLogForBugSplat:)]) {
        metadata.applicationLog = [self.delegate applicationLogForBugSplat:self];
    }
    
#if TARGET_OS_OSX
    // Get application key from delegate (macOS only)
    if ([self.delegate respondsToSelector:@selector(applicationKeyForBugSplat:signal:exceptionName:exceptionReason:)]) {
        // Parse signal/exception info from crash report if available
        PLCrashReport *report = [[PLCrashReport alloc] initWithData:crashData error:nil];
        NSString *signal = report.signalInfo.name;
        NSString *exceptionName = report.hasExceptionInfo ? report.exceptionInfo.exceptionName : nil;
        NSString *exceptionReason = report.hasExceptionInfo ? report.exceptionInfo.exceptionReason : nil;
        
        metadata.applicationKey = [self.delegate applicationKeyForBugSplat:self signal:signal exceptionName:exceptionName exceptionReason:exceptionReason];
    }
#endif
    
    // Convert text report to data for upload
    NSData *textCrashData = [crashReportText dataUsingEncoding:NSUTF8StringEncoding];
    if (!textCrashData) {
        NSLog(@"BugSplat: Failed to encode crash report text");
        [self.crashReporter purgePendingCrashReport];
        return;
    }
    
    // Upload
    [self.uploadService uploadCrashReport:textCrashData
                            crashFilename:@"crash.crashlog"
                              attachments:attachments
                                 metadata:metadata
                               completion:^(BOOL success, NSError *error) {
        if (success) {
            NSLog(@"BugSplat: Crash report uploaded successfully");
            
            // Only clear attributes and cleanup attachments after successful upload
            self.attributes = nil;
            [self cleanupPersistedAttachments];
            
            if ([self.delegate respondsToSelector:@selector(bugSplatDidFinishSendingCrashReport:)]) {
                [self.delegate bugSplatDidFinishSendingCrashReport:self];
            }
        } else {
            NSLog(@"BugSplat: Failed to upload crash report: %@", error);
            if ([self.delegate respondsToSelector:@selector(bugSplat:didFailWithError:)]) {
                [self.delegate bugSplat:self didFailWithError:error];
            }
        }
        
        // Purge the crash report
        [self.crashReporter purgePendingCrashReport];
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

#pragma mark - Attachment Persistence

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

- (void)persistAttachments:(NSArray<BugSplatAttachment *> *)attachments
{
    if (!attachments || attachments.count == 0) {
        return;
    }
    
    NSString *crashesDir = [self crashesDirectoryPath];
    if (!crashesDir) {
        return;
    }
    
    for (BugSplatAttachment *attachment in attachments) {
        NSString *filename = [NSString stringWithFormat:@"%@-%@.data", 
                              @([[NSDate date] timeIntervalSince1970]),
                              [[NSUUID UUID] UUIDString]];
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
    }
}

- (NSArray<BugSplatAttachment *> *)loadPersistedAttachments
{
    NSString *crashesDir = [self crashesDirectoryPath];
    if (!crashesDir) {
        return @[];
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:crashesDir error:&error];
    if (error) {
        NSLog(@"BugSplat: Failed to list crashes directory: %@", error);
        return @[];
    }
    
    NSMutableArray<BugSplatAttachment *> *attachments = [NSMutableArray array];
    
    for (NSString *filename in files) {
        if (![filename hasSuffix:@".data"]) {
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
    }
    
    return attachments;
}

- (void)cleanupPersistedAttachments
{
    NSString *crashesDir = [self crashesDirectoryPath];
    if (!crashesDir) {
        return;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:crashesDir error:&error];
    if (error) {
        return;
    }
    
    for (NSString *filename in files) {
        if ([filename hasSuffix:@".data"]) {
            NSString *filePath = [crashesDir stringByAppendingPathComponent:filename];
            [fileManager removeItemAtPath:filePath error:nil];
            NSLog(@"BugSplat: Cleaned up persisted attachment %@", filename);
        }
    }
}

@end
