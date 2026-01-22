//
//  MockCrashStorage.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "MockCrashStorage.h"

@interface MockCrashStorage ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *crashData;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *metadataStorage;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSData *> *> *attachmentsStorage;
@property (nonatomic, strong) NSMutableArray<NSString *> *cleanedUpFilenames;
@property (nonatomic, assign) NSUInteger cleanupAllCallCount;
@end

@implementation MockCrashStorage

- (instancetype)init
{
    self = [super init];
    if (self) {
        _crashData = [NSMutableDictionary dictionary];
        _metadataStorage = [NSMutableDictionary dictionary];
        _attachmentsStorage = [NSMutableDictionary dictionary];
        _cleanedUpFilenames = [NSMutableArray array];
        _cleanupAllCallCount = 0;
        _simulatedCrashesDirectoryPath = @"/mock/crashes";
    }
    return self;
}

- (void)reset
{
    [self.crashData removeAllObjects];
    [self.metadataStorage removeAllObjects];
    [self.attachmentsStorage removeAllObjects];
    [self.cleanedUpFilenames removeAllObjects];
    self.cleanupAllCallCount = 0;
}

- (void)addCrashWithFilename:(NSString *)filename 
                   crashData:(NSData *)data 
                    metadata:(NSDictionary *)metadata
{
    self.crashData[filename] = data;
    if (metadata) {
        self.metadataStorage[filename] = metadata;
    }
}

#pragma mark - BugSplatCrashStorageProtocol

- (NSString *)crashesDirectoryPath
{
    return self.simulatedCrashesDirectoryPath;
}

- (NSArray<NSString *> *)getPendingCrashFiles
{
    NSArray *filenames = self.crashData.allKeys;
    return [filenames sortedArrayUsingSelector:@selector(compare:)];
}

- (BOOL)persistCrashData:(NSData *)data withFilename:(NSString *)filename
{
    if (!data || !filename) {
        return NO;
    }
    self.crashData[filename] = data;
    return YES;
}

- (NSData *)loadCrashDataWithFilename:(NSString *)filename
{
    return self.crashData[filename];
}

- (BOOL)persistMetadata:(NSDictionary *)metadata forFilename:(NSString *)filename
{
    if (!metadata || !filename) {
        return NO;
    }
    self.metadataStorage[filename] = metadata;
    return YES;
}

- (NSDictionary *)loadMetadataForFilename:(NSString *)filename
{
    return self.metadataStorage[filename];
}

- (void)persistAttachmentsData:(NSArray<NSData *> *)attachmentsData forFilename:(NSString *)filename
{
    if (attachmentsData && filename) {
        self.attachmentsStorage[filename] = attachmentsData;
    }
}

- (NSArray<NSData *> *)loadAttachmentsDataForFilename:(NSString *)filename
{
    return self.attachmentsStorage[filename] ?: @[];
}

- (void)cleanupCrashReportWithFilename:(NSString *)filename
{
    [self.cleanedUpFilenames addObject:filename];
    [self.crashData removeObjectForKey:filename];
    [self.metadataStorage removeObjectForKey:filename];
    [self.attachmentsStorage removeObjectForKey:filename];
}

- (void)cleanupAllPendingCrashReports
{
    self.cleanupAllCallCount++;
    NSArray *allFilenames = [self.crashData.allKeys copy];
    for (NSString *filename in allFilenames) {
        [self cleanupCrashReportWithFilename:filename];
    }
}

@end
