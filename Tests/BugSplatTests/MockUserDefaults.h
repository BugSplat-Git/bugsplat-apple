//
//  MockUserDefaults.h
//  BugSplatTests
//
//  Mock implementation of user defaults for testing.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BugSplatTestSupport.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Mock user defaults for testing.
 */
@interface MockUserDefaults : NSObject <BugSplatUserDefaultsProtocol>

/**
 * Storage dictionary.
 */
@property (nonatomic, strong) NSMutableDictionary *storage;

/**
 * Reset all stored values.
 */
- (void)reset;

@end

NS_ASSUME_NONNULL_END
