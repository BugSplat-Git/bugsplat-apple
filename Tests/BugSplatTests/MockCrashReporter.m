//
//  MockCrashReporter.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "MockCrashReporter.h"

@interface MockCrashReporter ()
@property (nonatomic, assign) BOOL wasEnabled;
@property (nonatomic, assign) BOOL wasPurged;
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

@end
