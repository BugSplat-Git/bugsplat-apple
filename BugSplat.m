//
//  BugSplat.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <BugSplat/BugSplat.h>
#import <HockeySDK/HockeySDK.h>
#import "BugSplatUtilities.h"

NSString *const kHockeyIdentifierPlaceholder = @"b0cf675cb9334a3e96eda0764f95e38e";  // Just to satisfy Hockey since this is required
NSString *const kBugSplatUserDefaultsUserID = @"com.bugsplat.userID"; // UserDefaults key where BugSplat userID is stored
NSString *const kBugSplatUserDefaultsUserName = @"com.bugsplat.userName"; // UserDefaults key where BugSplat userName is stored
NSString *const kBugSplatUserDefaultsUserEmail = @"com.bugsplat.userEmail"; // UserDefaults key where BugSplat userEmail is stored
NSString *const kBugSplatUserDefaultsAttributes = @"com.bugsplat.attributes"; // UserDefaults key where BugSplat attributes are stored

@interface BugSplat() <BITHockeyManagerDelegate>

/** set to YES if start is called and returns successfully */
@property (atomic, assign) BOOL isStartInvoked;

/**
 * Attributes represent app supplied keys and values additional to the crash report.
 * Attributes will be bundled up in a BugSplatAttachment as NSData, with a filename of CrashContext.xml, MIME type of "application/xml" and encoding of "UTF-8".
 *
 * NOTES:
 *
 *
 * IMPORTANT: For iOS, if BugSplatDelegate's method `- (BugSplatAttachment *)attachmentForBugSplat:(BugSplat *)bugSplat` returns a non-nil BugSplatAttachment,
 * attributes will be ignored (NOT be included in the Crash Report). This is a current limitation of the iOS BugSplat API.
 */
@property (nonatomic, nullable) NSDictionary<NSString *, NSString *> *attributes;

@end

@implementation BugSplat

    // internal instance variable
    NSString * _bugSplatDatabase = nil;


+ (instancetype)shared
{
    static BugSplat *sharedInstance = nil;
    static dispatch_once_t pred;
    
    dispatch_once(&pred, ^{
        sharedInstance = [[BugSplat alloc] init];

        // load and erase any persisted attributes before `setValue:forAttribute:` API is available for this new app session.
        sharedInstance.attributes = [NSUserDefaults.standardUserDefaults dictionaryForKey:kBugSplatUserDefaultsAttributes];
        [NSUserDefaults.standardUserDefaults setValue:nil forKey:kBugSplatUserDefaultsAttributes];
    });
    
    return sharedInstance;
}

- (instancetype)init
{
    if (self = [super init]) {
        [[BITHockeyManager sharedHockeyManager] configureWithIdentifier:kHockeyIdentifierPlaceholder];

        self.isStartInvoked = NO;

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

    if (!self.bugSplatDatabase)
    {
        NSLog(@"*** BugSplatDatabase is nil. Please add this key/value to the your app's Info.plist or set bugSplatDatabase before invoking start. ***");

        // NSAssert is set to be ignored in this library in Release builds
        NSAssert(NO, @"*** BugSplatDatabase is nil. Please add this key/value to the your app's Info.plist or set bugSplatDatabase before invoking start. ***");
        self.isStartInvoked = NO; // unsuccessful return
        return;
    }

    if (self.isStartInvoked)
    {
        NSLog(@"*** BugSplat `start` was already invoked. ***");
        return;
    }

    NSLog(@"BugSplat BugSplatDatabase set as [%@]", self.bugSplatDatabase);
    NSString *serverURL = [NSString stringWithFormat: @"https://%@.bugsplat.com/", self.bugSplatDatabase];

    // Uncomment line below to enable HockeySDK logging
    // [[BITHockeyManager sharedHockeyManager] setLogLevel:BITLogLevelVerbose];

    NSLog(@"BugSplat setServerURL: [%@]", serverURL);
    [[BITHockeyManager sharedHockeyManager] setServerURL:serverURL];
    [[BITHockeyManager sharedHockeyManager] startManager];
    self.isStartInvoked = YES;
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

- (NSString *)bugSplatDatabase
{
    // defer to Info.plist value if present
    NSString *bugSplatDatabaseValue = (NSString *)[self.bundle objectForInfoDictionaryKey:kBugSplatDatabase];
    if (bugSplatDatabaseValue)
    {
        return [bugSplatDatabaseValue copy];
    }

    return _bugSplatDatabase;
}

- (void)setBugSplatDatabase:(NSString *)bugSplatDatabase
{
    // if a value is already present, do not change it
    if (self.bugSplatDatabase)
    {
        return;
    }

    // Set a value if value is not nil, and if isStartInvoked is NO
    if (bugSplatDatabase && !self.isStartInvoked)
    {
        _bugSplatDatabase = [bugSplatDatabase copy];
    }
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

/**
 * All attribute+value pairs are persisted in a `NSDictionary<NSString *, NSString *>` to NSUserDefaults under the key `kBugSplatUserDefaultsAttributes`.
 * Any attribute+value pairs persisted during an app session will be included as an attachment in a crash report if the app crashes in the session in which the attributes are set.
 * return NO if attribute is an invalid XML Entity name, otherwise returns YES.
 */
- (BOOL)setValue:(nullable NSString *)value forAttribute:(NSString *)attribute
{
    NSMutableDictionary<NSString *, NSString*> *mutableAttributes;
    NSDictionary<NSString *, NSString*> *persistedAttributes = [NSUserDefaults.standardUserDefaults dictionaryForKey:kBugSplatUserDefaultsAttributes];

    if (persistedAttributes == nil && value == nil)
    {
        return NO; // nil value and nil persistedAttributes
    }

    if (persistedAttributes)
    {
        mutableAttributes = [[NSMutableDictionary<NSString *, NSString *> alloc] initWithDictionary:persistedAttributes];
    }
    else {
        mutableAttributes = [NSMutableDictionary dictionary];
    }

    // first validate attribute as a valid entity name
    if (![attribute isValidXMLEntity])
    {
        return NO; // invalid attribute as xml entity
    }

    // xml clean up attribute
    // See: https://stackoverflow.com/questions/1091945/what-characters-do-i-need-to-escape-in-xml-documents

    // escape xml characters in value
    NSString *escapedValue = [value stringByEscapingXMLCharactersIgnoringCDataAndComments];

    NSLog(@"BugSplat [setValue:%@ forKey:%@]", escapedValue, attribute);

    // add to mutableAttributes dictionary
    [mutableAttributes setValue:escapedValue forKey:attribute];

    // persist newly updated mutableAttributes
    [NSUserDefaults.standardUserDefaults setValue:mutableAttributes forKey:kBugSplatUserDefaultsAttributes];
    return YES;
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

// iOS & MacOS
-(BITHockeyAttachment *)attachmentForCrashManager:(BITCrashManager *)crashManager
{
    if ([_delegate respondsToSelector:@selector(attachmentForBugSplat:)])
    {
        BugSplatAttachment *attachment = [_delegate attachmentForBugSplat:self];

        if (attachment)
        {
            return [[BITHockeyAttachment alloc] initWithFilename:attachment.filename
                                            hockeyAttachmentData:attachment.attachmentData
                                                     contentType:attachment.contentType];
        }
    }

    // if last session ended in a crash AND attributes were set in that session, build an attachment for the crash report
    if (crashManager.didCrashInLastSession && self.attributes)
    {
        NSDictionary<NSString *, NSString*> *attributes = self.attributes;
        self.attributes = nil; // do not reuse these attributes

        // no delegate provided BugSplatAttachment, send attributes as attributesAttachment if present
        BugSplatAttachment *attributesAttachment = [self bugSplatAttachmentWithAttributes:attributes];

        if (attributesAttachment)
        {
            return [[BITHockeyAttachment alloc] initWithFilename:attributesAttachment.filename
                                            hockeyAttachmentData:attributesAttachment.attachmentData
                                                     contentType:attributesAttachment.contentType];
        }
    }

    return nil;
}

// MacOS
#if TARGET_OS_OSX
- (NSArray<BITHockeyAttachment *> *)attachmentsForCrashManager:(BITCrashManager *)crashManager
{
    NSMutableArray *attachments = [[NSMutableArray alloc] init];

    if ([_delegate respondsToSelector:@selector(attachmentsForBugSplat:)])
    {
        NSArray *bugsplatAttachments = [_delegate attachmentsForBugSplat:self];

        for (BugSplatAttachment *attachment in bugsplatAttachments)
        {
            BITHockeyAttachment *hockeyAttachment = [[BITHockeyAttachment alloc] initWithFilename:attachment.filename
                                                                             hockeyAttachmentData:attachment.attachmentData
                                                                                      contentType:attachment.contentType];

            [attachments addObject:hockeyAttachment];
        }

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

        [attachments addObject:hockeyAttachment];
    }

    // if last session ended in a crash AND attributes were set in that session, build an attachment for the crash report
    if (crashManager.didCrashInLastSession && self.attributes)
    {
        NSDictionary<NSString *, NSString*> *attributes = self.attributes;
        self.attributes = nil; // do not reuse these attributes
        
        BugSplatAttachment *attributesAttachment = [self bugSplatAttachmentWithAttributes:attributes];
        if (attributesAttachment)
        {
            BITHockeyAttachment *hockeyAttachment = [[BITHockeyAttachment alloc] initWithFilename:attributesAttachment.filename
                                                                             hockeyAttachmentData:attributesAttachment.attachmentData
                                                                                      contentType:attributesAttachment.contentType];
            [attachments addObject:hockeyAttachment];
        }
    }

    if ([attachments count] > 0)
    {
        return [attachments copy];
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

// iOS
#else

-(void)crashManagerWillSendCrashReportsAlways:(BITCrashManager *)crashManager
{
    if ([_delegate respondsToSelector:@selector(bugSplatWillSendCrashReportsAlways:)])
    {
        [_delegate bugSplatWillSendCrashReportsAlways:self];
    }
}

#endif

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

/**
 * If attributes are present, bundle them up as a BugSplatAttachment containing
 * NSData created from NSString representing an XML file, filename of CrashContext.xml, MIME type of "application/xml" and encoding of "UTF-8".
 */
- (BugSplatAttachment *)bugSplatAttachmentWithAttributes:(NSDictionary *)attributes
{
    if (attributes == nil || [attributes count] == 0)
    {
        return nil;
    }

    // prepare XML as stringData from attributes
    // NOTE: If NSXMLDocument was available for iOS, that would be the better choice for building our XMLDocument...

    NSMutableString *stringData = [NSMutableString new];
    [stringData appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [stringData appendString:@"<Attributes>\n"];

    // for each attribute:value pair, add <attribute>value</attribute> row to the XML stringData
    for (NSString *attribute in attributes.allKeys) {
        NSString *value = attributes[attribute];
        [stringData appendFormat:@"<%@>", attribute];
        [stringData appendString:value];
        [stringData appendFormat:@"</%@>", attribute];
        [stringData appendString:@"\n"];
    }

    [stringData appendString:@"</Attributes>\n"];

    NSData *data = [stringData dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];

    if (data)
    {
        // debug logging
        NSString *debugString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (debugString)
        {
            NSLog(@"BugSplat adding attributes as BugSplatAttachment with contents: [%@]", debugString);
        }

        return [[BugSplatAttachment alloc] initWithFilename:@"CrashContext.xml" attachmentData:data contentType:@"UTF-8"];
    }

    return nil;
}

- (NSString *)userIDForHockeyManager:(BITHockeyManager *)hockeyManager componentManager:(BITHockeyBaseManager *)componentManager
{
    return [self userID];
}

- (NSString *)userNameForHockeyManager:(BITHockeyManager *)hockeyManager componentManager:(BITHockeyBaseManager *)componentManager
{
    return [self userName];
}

- (NSString *)userEmailForHockeyManager:(BITHockeyManager *)hockeyManager componentManager:(BITHockeyBaseManager *)componentManager
{
    return [self userEmail];
}

/**
 * This optional delegate callback is called when the user submits a crash report after manually entering in meta data for the crash report.
 */
- (void)userProvidedData:(BITHockeyUserData *)userProvidedData hockeyManager:(BITHockeyManager *)hockeyManager componentManager:(BITHockeyBaseManager *)componentManager
{
    if (!userProvidedData) return;

#if TARGET_OS_OSX
    if ([self persistUserDetails] == NO) {
        return;
    }
#endif

    [self setUserName:userProvidedData.userName];
    [self setUserEmail:userProvidedData.userEmail];
}


@end
