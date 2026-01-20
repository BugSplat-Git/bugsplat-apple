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

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.filename forKey:@"filename"];
    [coder encodeObject:self.attachmentData forKey:@"attachmentData"];
    [coder encodeObject:self.contentType forKey:@"contentType"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super init])
    {
        self.filename = [coder decodeObjectOfClass:[NSString class] forKey:@"filename"];
        self.attachmentData = [coder decodeObjectOfClass:[NSData class] forKey:@"attachmentData"];
        self.contentType = [coder decodeObjectOfClass:[NSString class] forKey:@"contentType"];
    }
    return self;
}

@end
