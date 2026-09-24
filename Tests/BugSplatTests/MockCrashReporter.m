//
//  MockCrashReporter.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "MockCrashReporter.h"

#import <BugSplat/BugSplat.h>

#import "BugSplat+Testing.h"

@interface MockCrashReporter ()
@property (nonatomic, assign) BOOL wasEnabled;
@property (nonatomic, assign) BOOL wasPurged;
@property (nonatomic, assign) NSUInteger liveReportCallCount;
@property (nonatomic, strong, nullable) NSException *lastLiveReportException;
@end

@implementation MockCrashReporter

- (instancetype)init
{
    self = [super init];
    if (self) {
        _hasPendingReport = NO;
        _wasEnabled = NO;
        _wasPurged = NO;
    }
    return self;
}

- (void)reset
{
    self.hasPendingReport = NO;
    self.pendingCrashReportData = nil;
    self.loadError = nil;
    self.enableError = nil;
    self.customData = nil;
    self.wasEnabled = NO;
    self.wasPurged = NO;
    self.liveReportData = nil;
    self.liveReportError = nil;
    self.liveReportCallCount = 0;
    self.lastLiveReportException = nil;
}

+ (NSData *)liveReportDataWithException:(NSException *)exception
{
    // A plain (non-test) instance carries a real PLCrashReporter, which can capture a live
    // report without the crash handler being enabled.
    BugSplat *realInstance = [[BugSplat alloc] init];
    id<BugSplatCrashReporterProtocol> reporter = [realInstance crashReporter];

    NSError *error = nil;
    return [reporter generateLiveReportWithException:exception error:&error];
}

#pragma mark - BugSplatCrashReporterProtocol

- (BOOL)hasPendingCrashReport
{
    return self.hasPendingReport;
}

- (NSData *)loadPendingCrashReportDataAndReturnError:(NSError **)outError
{
    if (self.loadError) {
        if (outError) {
            *outError = self.loadError;
        }
        return nil;
    }
    return self.pendingCrashReportData;
}

- (void)purgePendingCrashReport
{
    self.wasPurged = YES;
    self.hasPendingReport = NO;
    self.pendingCrashReportData = nil;
}

- (BOOL)enableCrashReporterAndReturnError:(NSError **)outError
{
    if (self.enableError) {
        if (outError) {
            *outError = self.enableError;
        }
        return NO;
    }
    self.wasEnabled = YES;
    return YES;
}

- (NSData *)generateLiveReportWithException:(NSException *)exception error:(NSError **)outError
{
    self.liveReportCallCount += 1;
    self.lastLiveReportException = exception;

    if (self.liveReportError) {
        if (outError) {
            *outError = self.liveReportError;
        }
        return nil;
    }
    return self.liveReportData;
}

@end
