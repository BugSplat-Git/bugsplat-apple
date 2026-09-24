//
//  BugSplatCrashInfo.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BugSplatCrashInfo.h"

@implementation BugSplatCrashInfo

- (instancetype)initWithType:(BugSplatCrashInfoType)type
                   sessionID:(nullable NSUUID *)sessionID
                   crashDate:(nullable NSDate *)crashDate
             applicationName:(nullable NSString *)applicationName
          applicationVersion:(nullable NSString *)applicationVersion
               userSubmitted:(BOOL)userSubmitted
{
    if ((self = [super init]))
    {
        _type = type;
        _sessionID = [sessionID copy];
        _crashDate = [crashDate copy];
        _applicationName = [applicationName copy];
        _applicationVersion = [applicationVersion copy];
        _userSubmitted = userSubmitted;
    }
    return self;
}

+ (NSString *)descriptionForType:(BugSplatCrashInfoType)type
{
    switch (type) {
        case BugSplatCrashInfoTypeFatalHang:    return @"fatalHang";
        case BugSplatCrashInfoTypeNonFatalHang: return @"nonFatalHang";
        case BugSplatCrashInfoTypeCrash:        break;
    }
    return @"crash";
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: type=%@, sessionID=%@, crashDate=%@, application=%@ %@, userSubmitted=%@>",
            NSStringFromClass([self class]),
            [[self class] descriptionForType:self.type],
            self.sessionID.UUIDString,
            self.crashDate,
            self.applicationName,
            self.applicationVersion,
            self.userSubmitted ? @"YES" : @"NO"];
}

@end
