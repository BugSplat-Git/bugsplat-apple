//
//  BugSplat.m
//
//  Copyright © 2024 BugSplat, LLC. All rights reserved.
//

#import <BugSplat/BugSplat.h>
#import <HockeySDK/HockeySDK.h>
#import "BugSplatUtilities.h"

NSString *const kHockeyIdentifierPlaceholder = @"b0cf675cb9334a3e96eda0764f95e38e";  // Just to satisfy Hockey since this is required

@interface BugSplat() <BITHockeyManagerDelegate>

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
@property (nonatomic, nullable) NSMutableDictionary<NSString *, NSString *> *attributes;

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

- (void)setValue:(nullable NSString *)value forAttribute:(NSString *)attribute
{
    if (_attributes == nil && value != nil) {
        _attributes = [NSMutableDictionary dictionary];
    }

    // clean up attribute and values
    // See: https://stackoverflow.com/questions/1091945/what-characters-do-i-need-to-escape-in-xml-documents

    // first remove newlines and whitespace from prefix or suffix of an attribute since these will be nodes in the XML document
    NSString *cleanedUpAttribute = [attribute stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *escapedAttribute = [cleanedUpAttribute stringByEscapingXMLCharactersIgnoringCDataAndComments];

    // escape xml characters in value
    NSString *escapedValue = [value stringByEscapingXMLCharactersIgnoringCDataAndComments];

    NSLog(@"BugSplat adding attribute [_attributes setValue%@ forKey:%@]", escapedValue, escapedAttribute);

    // add to _attributes dictionary
    [_attributes setValue:escapedValue forKey:escapedAttribute];
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

        if (attachment)
        {
            return [[BITHockeyAttachment alloc] initWithFilename:attachment.filename
                                            hockeyAttachmentData:attachment.attachmentData
                                                     contentType:attachment.contentType];
        }
    }

    // no delegate provided BugSplatAttachment, send attributes as attributesAttachment if present
    BugSplatAttachment *attributesAttachment = [self bugSplatAttachmentWithAttributes:self.attributes];
    if (attributesAttachment)
    {
        return [[BITHockeyAttachment alloc] initWithFilename:attributesAttachment.filename
                                        hockeyAttachmentData:attributesAttachment.attachmentData
                                                 contentType:attributesAttachment.contentType];
    }

    return nil;
}

// MacOS
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

    // include attributes as attributesAttachment if present
    BugSplatAttachment *attributesAttachment = [self bugSplatAttachmentWithAttributes:self.attributes];
    if (attributesAttachment)
    {
        BITHockeyAttachment *hockeyAttachment = [[BITHockeyAttachment alloc] initWithFilename:attributesAttachment.filename
                                                                         hockeyAttachmentData:attributesAttachment.attachmentData
                                                                                  contentType:attributesAttachment.contentType];
        [attachments addObject:hockeyAttachment];
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
    [stringData appendString:@"<FGenericCrashContext>\n"];
    [stringData appendString:@"<RuntimeProperties>\n"];

    // for each attribute:value pair, add <attribute>value</attribute> row to the XML stringData
    for (NSString *attribute in attributes.allKeys) {
        NSString *value = attributes[attribute];
        [stringData appendFormat:@"<%@>", attribute];
        [stringData appendString:value];
        [stringData appendFormat:@"</%@>", attribute];
        [stringData appendString:@"\n"];
    }

    [stringData appendString:@"</RuntimeProperties>\n"];
    [stringData appendString:@"</FGenericCrashContext>\n"];

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

@end
