//
//  MockBundle.h
//  BugSplatTests
//
//  Mock implementation of bundle for testing.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BugSplatTestSupport.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Mock bundle for testing Info.plist value access.
 */
@interface MockBundle : NSObject <BugSplatBundleProtocol>

/**
 * Dictionary of values to return for Info.plist keys.
 */
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *infoDictionary;

/**
 * Set a value for an Info.plist key.
 */
- (void)setObject:(nullable id)value forInfoDictionaryKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
