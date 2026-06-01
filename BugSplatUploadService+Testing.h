//
//  BugSplatUploadService+Testing.h
//
//  Private testing interface for BugSplatUploadService.
//  This header exposes internal seams for unit testing and must not be
//  imported by production code.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BugSplatUploadService.h"

NS_ASSUME_NONNULL_BEGIN

@interface BugSplatUploadService ()

/**
 * Overrides how completion handlers are delivered.
 *
 * Production always delivers completions asynchronously on the main queue.
 * Tests inject a synchronous dispatcher so the multi-step upload flow runs to
 * completion without depending on the run loop draining queued main-queue
 * blocks (which flakes under heavy CI/simulator load).
 */
- (void)setCompletionDispatcher:(void (^)(dispatch_block_t block))completionDispatcher;

@end

NS_ASSUME_NONNULL_END
