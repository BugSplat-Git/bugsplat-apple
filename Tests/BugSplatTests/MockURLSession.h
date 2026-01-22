//
//  MockURLSession.h
//  BugSplatTests
//
//  Mock implementation of URL session for testing network code.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BugSplatTestSupport.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents a recorded network request for verification.
 */
@interface MockURLSessionRequest : NSObject

@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic, strong, nullable) NSData *bodyData;
@property (nonatomic, assign) BOOL isUploadTask;

@end


/**
 * Mock URL session for testing network operations.
 */
@interface MockURLSession : NSObject <BugSplatURLSessionProtocol>

/**
 * Configure the response for the next request.
 */
@property (nonatomic, strong, nullable) NSData *nextResponseData;
@property (nonatomic, strong, nullable) NSHTTPURLResponse *nextResponse;
@property (nonatomic, strong, nullable) NSError *nextError;

/**
 * Array of all recorded requests.
 */
@property (nonatomic, readonly) NSArray<MockURLSessionRequest *> *recordedRequests;

/**
 * Number of requests made.
 */
@property (nonatomic, readonly) NSUInteger requestCount;

/**
 * The last request made.
 */
@property (nonatomic, readonly, nullable) MockURLSessionRequest *lastRequest;

/**
 * Whether to call completion handler synchronously (default: YES for testing).
 */
@property (nonatomic, assign) BOOL completeSynchronously;

/**
 * Queue multiple responses for sequential requests.
 */
- (void)queueResponseWithData:(nullable NSData *)data 
                     response:(nullable NSHTTPURLResponse *)response 
                        error:(nullable NSError *)error;

/**
 * Create a successful response with the given status code.
 */
+ (NSHTTPURLResponse *)responseWithStatusCode:(NSInteger)statusCode;

/**
 * Create a successful JSON response.
 */
+ (NSHTTPURLResponse *)jsonResponseWithStatusCode:(NSInteger)statusCode;

/**
 * Reset the mock to its initial state.
 */
- (void)reset;

@end


/**
 * Mock URL session task that immediately completes.
 */
@interface MockURLSessionDataTask : NSURLSessionDataTask

@property (nonatomic, copy, nullable) void (^resumeBlock)(void);

@end


@interface MockURLSessionUploadTask : NSURLSessionUploadTask

@property (nonatomic, copy, nullable) void (^resumeBlock)(void);

@end

NS_ASSUME_NONNULL_END
