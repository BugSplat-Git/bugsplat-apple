//
//  MockBundle.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "MockBundle.h"

@implementation MockBundle

- (instancetype)init
{
    self = [super init];
    if (self) {
        _infoDictionary = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setObject:(id)value forInfoDictionaryKey:(NSString *)key
{
    if (value) {
        self.infoDictionary[key] = value;
    } else {
        [self.infoDictionary removeObjectForKey:key];
    }
}

#pragma mark - BugSplatBundleProtocol

- (id)objectForInfoDictionaryKey:(NSString *)key
{
    return self.infoDictionary[key];
}

@end
