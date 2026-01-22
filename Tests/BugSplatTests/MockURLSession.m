//
//  MockURLSession.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "MockURLSession.h"

@implementation MockURLSessionRequest
@end


@interface MockQueuedResponse : NSObject
@property (nonatomic, strong, nullable) NSData *data;
@property (nonatomic, strong, nullable) NSHTTPURLResponse *response;
@property (nonatomic, strong, nullable) NSError *error;
@end

@implementation MockQueuedResponse
@end


@interface MockURLSession ()
@property (nonatomic, strong) NSMutableArray<MockURLSessionRequest *> *mutableRecordedRequests;
@property (nonatomic, strong) NSMutableArray<MockQueuedResponse *> *queuedResponses;
@end

@implementation MockURLSession

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mutableRecordedRequests = [NSMutableArray array];
        _queuedResponses = [NSMutableArray array];
        _completeSynchronously = YES;
    }
    return self;
}

- (NSArray<MockURLSessionRequest *> *)recordedRequests
{
    return [self.mutableRecordedRequests copy];
}

- (NSUInteger)requestCount
{
    return self.mutableRecordedRequests.count;
}

- (MockURLSessionRequest *)lastRequest
{
    return self.mutableRecordedRequests.lastObject;
}

- (void)queueResponseWithData:(NSData *)data response:(NSHTTPURLResponse *)response error:(NSError *)error
{
    MockQueuedResponse *queuedResponse = [[MockQueuedResponse alloc] init];
    queuedResponse.data = data;
    queuedResponse.response = response;
    queuedResponse.error = error;
    [self.queuedResponses addObject:queuedResponse];
}

+ (NSHTTPURLResponse *)responseWithStatusCode:(NSInteger)statusCode
{
    return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                       statusCode:statusCode
                                      HTTPVersion:@"HTTP/1.1"
                                     headerFields:nil];
}

+ (NSHTTPURLResponse *)jsonResponseWithStatusCode:(NSInteger)statusCode
{
    return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                       statusCode:statusCode
                                      HTTPVersion:@"HTTP/1.1"
                                     headerFields:@{@"Content-Type": @"application/json"}];
}

- (void)reset
{
    [self.mutableRecordedRequests removeAllObjects];
    [self.queuedResponses removeAllObjects];
    self.nextResponseData = nil;
    self.nextResponse = nil;
    self.nextError = nil;
}

- (void)getNextResponseData:(NSData **)data response:(NSHTTPURLResponse **)response error:(NSError **)error
{
    if (self.queuedResponses.count > 0) {
        MockQueuedResponse *queued = self.queuedResponses.firstObject;
        [self.queuedResponses removeObjectAtIndex:0];
        *data = queued.data;
        *response = queued.response;
        *error = queued.error;
    } else {
        *data = self.nextResponseData;
        *response = self.nextResponse;
        *error = self.nextError;
    }
}

#pragma mark - BugSplatURLSessionProtocol

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
    MockURLSessionRequest *recordedRequest = [[MockURLSessionRequest alloc] init];
    recordedRequest.request = request;
    recordedRequest.isUploadTask = NO;
    [self.mutableRecordedRequests addObject:recordedRequest];
    
    NSData *responseData;
    NSHTTPURLResponse *response;
    NSError *error;
    [self getNextResponseData:&responseData response:&response error:&error];
    
    MockURLSessionDataTask *task = [[MockURLSessionDataTask alloc] init];
    
    if (self.completeSynchronously) {
        task.resumeBlock = ^{
            completionHandler(responseData, response, error);
        };
    } else {
        task.resumeBlock = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(responseData, response, error);
            });
        };
    }
    
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
    MockURLSessionRequest *recordedRequest = [[MockURLSessionRequest alloc] init];
    recordedRequest.request = request;
    recordedRequest.bodyData = bodyData;
    recordedRequest.isUploadTask = YES;
    [self.mutableRecordedRequests addObject:recordedRequest];
    
    NSData *responseData;
    NSHTTPURLResponse *response;
    NSError *error;
    [self getNextResponseData:&responseData response:&response error:&error];
    
    MockURLSessionUploadTask *task = [[MockURLSessionUploadTask alloc] init];
    
    if (self.completeSynchronously) {
        task.resumeBlock = ^{
            completionHandler(responseData, response, error);
        };
    } else {
        task.resumeBlock = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(responseData, response, error);
            });
        };
    }
    
    return task;
}

- (void)invalidateAndCancel
{
    // No-op for mock
}

@end


@implementation MockURLSessionDataTask

- (void)resume
{
    if (self.resumeBlock) {
        self.resumeBlock();
    }
}

- (void)cancel
{
    // No-op for mock
}

@end


@implementation MockURLSessionUploadTask

- (void)resume
{
    if (self.resumeBlock) {
        self.resumeBlock();
    }
}

- (void)cancel
{
    // No-op for mock
}

@end
