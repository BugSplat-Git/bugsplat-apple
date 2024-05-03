//
//  BugSplat.m
//
//  Copyright © 2024 BugSplat, LLC. All rights reserved.
//

#import <BugSplat/BugSplat.h>
#import <HockeySDK/HockeySDK.h>

NSString *const kHockeyIdentifierPlaceholder = @"b0cf675cb9334a3e96eda0764f95e38e";  // Just to satisfy Hockey since this is required

@interface BugSplat() <BITHockeyManagerDelegate>

@end

@implementation BugSplat

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
        [[BITHockeyManager sharedHockeyManager] configureWithIdentifier:kHockeyIdentifierPlaceholder];

#if TARGET_OS_OSX
        _autoSubmitCrashReport = NO;
        _askUserDetails = YES;
        _expirationTimeInterval = -1;

        NSImage *bannerImage = [NSImage imageNamed:@"bugsplat-logo"];

        if (bannerImage) {
            self.bannerImage = bannerImage;
        }
#endif
    }

    return self;
}

- (void)start
{
    NSLog(@"BugSplat start...");

    id bugSplatDatabaseValue = [self.bundle objectForInfoDictionaryKey:kBugSplatDatabase];
    if (bugSplatDatabaseValue == nil) {
        NSLog(@"*** BugSplatDatabase is missing from your Info.plist - Please add this key/value to the your app's Info.plist ***");

        // NSAssert is set to be ignored in this library in Release builds
        NSAssert(NO, @"BugSplatDatabase is missing from your Info.plist - Please add this key/value to the your app's Info.plist");
    }

    NSString *bugSplatDatabase = (NSString *)bugSplatDatabaseValue;
    NSLog(@"BugSplat BugSplatDatabase set as [%@]", bugSplatDatabase);

    NSString *serverURL = [NSString stringWithFormat: @"https://%@.bugsplat.com/", bugSplatDatabase];

    // Uncomment line below to enable HockeySDK logging
//    [[BITHockeyManager sharedHockeyManager] setLogLevel:BITLogLevelVerbose];

    NSLog(@"BugSplat setServerURL: [%@]", serverURL);
    [[BITHockeyManager sharedHockeyManager] setServerURL:serverURL];
    [[BITHockeyManager sharedHockeyManager] startManager];
}

- (void)setDelegate:(id<BugSplatDelegate>)delegate
{
    if (_delegate != delegate)
    {
        _delegate = delegate;
    }
    
    [[BITHockeyManager sharedHockeyManager] setDelegate:self];
}

- (NSBundle *)bundle
{
    return [NSBundle mainBundle]; // return app's main bundle, not BugSplat framework's bundle
}

- (void)setUserID:(NSString *)userID
{
    _userID = userID;
    [[BITHockeyManager sharedHockeyManager] setUserID:userID];
}

- (void)setUserName:(NSString *)userName
{
    _userName = userName;
    [[BITHockeyManager sharedHockeyManager] setUserName:userName];
}

- (void)setUserEmail:(NSString *)userEmail
{
    _userEmail = userEmail;
    [[BITHockeyManager sharedHockeyManager] setUserEmail:userEmail];
}

- (void)setAutoSubmitCrashReport:(BOOL)autoSubmitCrashReport
{
    _autoSubmitCrashReport = autoSubmitCrashReport;

#if TARGET_OS_OSX
    [[[BITHockeyManager sharedHockeyManager] crashManager] setAutoSubmitCrashReport:self.autoSubmitCrashReport];
#else
    BITCrashManagerStatus crashManagerStatus = autoSubmitCrashReport ? BITCrashManagerStatusAutoSend : BITCrashManagerStatusAlwaysAsk;
    [[[BITHockeyManager sharedHockeyManager] crashManager] setCrashManagerStatus:crashManagerStatus];
#endif

}


#if TARGET_OS_OSX

- (void)setBannerImage:(NSImage *)bannerImage
{
    _bannerImage = bannerImage;
    [[[BITHockeyManager sharedHockeyManager] crashManager] setBannerImage:self.bannerImage];
}

- (void)setAskUserDetails:(BOOL)askUserDetails
{
    _askUserDetails = askUserDetails;
    [[[BITHockeyManager sharedHockeyManager] crashManager] setAskUserDetails:self.askUserDetails];
}

- (void)setPersistUserDetails:(BOOL)persistUserDetails
{
    _persistUserDetails = persistUserDetails;
    [[[BITHockeyManager sharedHockeyManager] crashManager] setPersistUserInfo:self.persistUserDetails];
}

- (void)setExpirationTimeInterval:(NSTimeInterval)expirationTimeInterval
{
    _expirationTimeInterval = expirationTimeInterval;
    [[[BITHockeyManager sharedHockeyManager] crashManager] setExpirationTimeInterval:self.expirationTimeInterval];
}

- (void)setPresentModally:(BOOL)presentModally
{
    _presentModally = presentModally;
    [[[BITHockeyManager sharedHockeyManager] crashManager] setPresentModally:_presentModally];
}
#endif


#pragma mark - BITHockeyManagerDelegate

- (NSString *)applicationLogForCrashManager:(BITCrashManager *)crashManager
{
    if ([_delegate respondsToSelector:@selector(applicationLogForBugSplat:)])
    {
        return [_delegate applicationLogForBugSplat:self];
    }
    
    return nil;
}

// iOS
-(BITHockeyAttachment *)attachmentForCrashManager:(BITCrashManager *)crashManager
{
    if ([_delegate respondsToSelector:@selector(attachmentForBugSplat:)])
    {
        BugSplatAttachment *attachment = [_delegate attachmentForBugSplat:self];
        
        return [[BITHockeyAttachment alloc] initWithFilename:attachment.filename
                                        hockeyAttachmentData:attachment.attachmentData
                                                 contentType:attachment.contentType];
    }
    
    return nil;
}

// MacOS
- (NSArray<BITHockeyAttachment *> *)attachmentsForCrashManager:(BITCrashManager *)crashManager
{
    if ([_delegate respondsToSelector:@selector(attachmentsForBugSplat:)])
    {
        NSMutableArray *attachments = [[NSMutableArray alloc] init];

        NSArray *bugsplatAttachments = [_delegate attachmentsForBugSplat:self];

        for (BugSplatAttachment *attachment in bugsplatAttachments)
        {
            BITHockeyAttachment *hockeyAttachment = [[BITHockeyAttachment alloc] initWithFilename:attachment.filename
                                                                             hockeyAttachmentData:attachment.attachmentData
                                                                                      contentType:attachment.contentType];

            [attachments addObject:hockeyAttachment];
        }

        return [attachments copy];
    }
    else if ([_delegate respondsToSelector:@selector(attachmentForBugSplat:)])
    {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

        BugSplatAttachment *attachment = [_delegate attachmentForBugSplat:self];

#pragma clang diagnostic pop

        BITHockeyAttachment *hockeyAttachment = [[BITHockeyAttachment alloc] initWithFilename:attachment.filename
                                                                         hockeyAttachmentData:attachment.attachmentData
                                                                                  contentType:attachment.contentType];

        return @[hockeyAttachment];
    }

    return nil;
}

// MacOS
- (NSString *)applicationKeyForCrashManager:(BITCrashManager *)crashManager signal:(NSString *)signal exceptionName:(NSString *)exceptionName exceptionReason:(NSString *)exceptionReason
{
    if ([_delegate respondsToSelector:@selector(applicationKeyForBugSplat:signal:exceptionName:exceptionReason:)])
    {
        return [_delegate applicationKeyForBugSplat:self signal:signal exceptionName:exceptionName exceptionReason:exceptionReason];
    }
    
    return nil;
}

- (void)crashManagerWillShowSubmitCrashReportAlert:(BITCrashManager *)crashManager
{
    if ([_delegate respondsToSelector:@selector(bugSplatWillShowSubmitCrashReportAlert:)])
    {
        [_delegate bugSplatWillShowSubmitCrashReportAlert:self];
    }
}

- (void)crashManagerWillCancelSendingCrashReport:(BITCrashManager *)crashManager
{
    if ([_delegate respondsToSelector:@selector(bugSplatWillCancelSendingCrashReport:)])
    {
        [_delegate bugSplatWillCancelSendingCrashReport:self];
    }
}

- (void)crashManagerWillSendCrashReport:(BITCrashManager *)crashManager
{
    if ([_delegate respondsToSelector:@selector(bugSplatWillSendCrashReport:)])
    {
        [_delegate bugSplatWillSendCrashReport:self];
    }
}

- (void)crashManager:(BITCrashManager *)crashManager didFailWithError:(NSError *)error
{
    if ([_delegate respondsToSelector:@selector(bugSplat:didFailWithError:)])
    {
        [_delegate bugSplat:self didFailWithError:error];
    }
}

- (void)crashManagerDidFinishSendingCrashReport:(BITCrashManager *)crashManager
{
    if ([_delegate respondsToSelector:@selector(bugSplatDidFinishSendingCrashReport:)])
    {
        [_delegate bugSplatDidFinishSendingCrashReport:self];
    }
}

@end
