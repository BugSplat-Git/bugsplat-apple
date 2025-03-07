//
//  BugSplatAttachment.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BugSplatAttachment.h"

@interface BugSplatAttachment ()

@property (nonatomic, strong) NSString *filename;
@property (nonatomic, strong) NSData *attachmentData;
@property (nonatomic, strong) NSString *contentType;

@end

@implementation BugSplatAttachment

- (instancetype)initWithFilename:(NSString *)filename attachmentData:(NSData *)attachmentData contentType:(NSString *)contentType
{
    if (self = [super init])
    {
        self.filename = filename;
        self.attachmentData = attachmentData;
        self.contentType = contentType;
    }
    
    return self;
}

@end
