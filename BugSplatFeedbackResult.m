//
//  BugSplatFeedbackResult.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BugSplatFeedbackResult.h"

@implementation BugSplatFeedbackResult

- (instancetype)initWithCrashId:(nullable NSNumber *)crashId infoUrl:(nullable NSString *)infoUrl
{
    if ((self = [super init]))
    {
        _crashId = [crashId copy];
        _infoUrl = [infoUrl copy];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: crashId=%@, infoUrl=%@>",
            NSStringFromClass([self class]), self.crashId, self.infoUrl];
}

@end
