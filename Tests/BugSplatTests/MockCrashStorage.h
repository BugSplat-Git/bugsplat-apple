//
//  MockCrashStorage.h
//  BugSplatTests
//
//  Mock implementation of crash storage for testing.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BugSplatTestSupport.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Mock crash storage that uses in-memory storage for testing.
 */
@interface MockCrashStorage : NSObject <BugSplatCrashStorageProtocol>

/**
 * In-memory storage for crash data.
 */
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSData *> *crashData;

/**
 * In-memory storage for metadata.
 */
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSDictionary *> *metadataStorage;

/**
 * In-memory storage for attachments.
 */
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSArray<NSData *> *> *attachmentsStorage;

/**
 * Simulated crashes directory path (for verification).
 */
@property (nonatomic, copy) NSString *simulatedCrashesDirectoryPath;

/**
 * Track cleanup calls for verification.
 */
@property (nonatomic, readonly) NSMutableArray<NSString *> *cleanedUpFilenames;
@property (nonatomic, readonly) NSUInteger cleanupAllCallCount;

/**
 * Reset all storage and tracking.
 */
- (void)reset;

/**
 * Add a crash file to the mock storage.
 */
- (void)addCrashWithFilename:(NSString *)filename 
                   crashData:(NSData *)data 
                    metadata:(nullable NSDictionary *)metadata;

@end

NS_ASSUME_NONNULL_END
