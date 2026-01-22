//
//  MockUserDefaults.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "MockUserDefaults.h"

@implementation MockUserDefaults

- (instancetype)init
{
    self = [super init];
    if (self) {
        _storage = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)reset
{
    [self.storage removeAllObjects];
}

#pragma mark - BugSplatUserDefaultsProtocol

- (NSString *)stringForKey:(NSString *)defaultName
{
    id value = self.storage[defaultName];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return nil;
}

- (BOOL)boolForKey:(NSString *)defaultName
{
    id value = self.storage[defaultName];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value boolValue];
    }
    return NO;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName
{
    if (value) {
        self.storage[defaultName] = value;
    } else {
        [self.storage removeObjectForKey:defaultName];
    }
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName
{
    self.storage[defaultName] = @(value);
}

@end
