//
//  BugSplatAttachmentTests.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "BugSplatAttachment.h"

@interface BugSplatAttachmentTests : XCTestCase
@end

@implementation BugSplatAttachmentTests

#pragma mark - Initialization Tests

- (void)testInit_SetsAllProperties
{
    NSString *filename = @"test.log";
    NSData *data = [@"log content" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *contentType = @"text/plain";
    
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:filename
                                                                   attachmentData:data
                                                                      contentType:contentType];
    
    XCTAssertEqualObjects(attachment.filename, filename);
    XCTAssertEqualObjects(attachment.attachmentData, data);
    XCTAssertEqualObjects(attachment.contentType, contentType);
}

- (void)testInit_WithBinaryData
{
    NSString *filename = @"screenshot.png";
    uint8_t pngHeader[] = {0x89, 0x50, 0x4E, 0x47}; // PNG magic bytes
    NSData *data = [NSData dataWithBytes:pngHeader length:4];
    NSString *contentType = @"image/png";
    
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:filename
                                                                   attachmentData:data
                                                                      contentType:contentType];
    
    XCTAssertEqualObjects(attachment.filename, filename);
    XCTAssertEqualObjects(attachment.attachmentData, data);
    XCTAssertEqualObjects(attachment.contentType, contentType);
}

- (void)testInit_WithEmptyData
{
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:@"empty.txt"
                                                                   attachmentData:[NSData data]
                                                                      contentType:@"text/plain"];
    
    XCTAssertNotNil(attachment);
    XCTAssertEqual(attachment.attachmentData.length, 0);
}

- (void)testInit_WithLargeData
{
    NSMutableData *largeData = [NSMutableData dataWithLength:1024 * 1024]; // 1MB
    memset(largeData.mutableBytes, 'A', largeData.length);
    
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:@"large.bin"
                                                                   attachmentData:largeData
                                                                      contentType:@"application/octet-stream"];
    
    XCTAssertNotNil(attachment);
    XCTAssertEqual(attachment.attachmentData.length, 1024 * 1024);
}

#pragma mark - NSSecureCoding Tests

- (void)testSupportsSecureCoding
{
    XCTAssertTrue([BugSplatAttachment supportsSecureCoding]);
}

- (void)testSecureCoding_RoundTrip
{
    NSString *filename = @"test.log";
    NSData *data = [@"log content here" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *contentType = @"text/plain";
    
    BugSplatAttachment *original = [[BugSplatAttachment alloc] initWithFilename:filename
                                                                 attachmentData:data
                                                                    contentType:contentType];
    
    // Encode
    NSError *archiveError = nil;
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:original
                                                 requiringSecureCoding:YES
                                                                 error:&archiveError];
    XCTAssertNil(archiveError);
    XCTAssertNotNil(archivedData);
    
    // Decode
    NSError *unarchiveError = nil;
    BugSplatAttachment *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[BugSplatAttachment class]
                                                                    fromData:archivedData
                                                                       error:&unarchiveError];
    XCTAssertNil(unarchiveError);
    XCTAssertNotNil(decoded);
    
    // Verify
    XCTAssertEqualObjects(decoded.filename, original.filename);
    XCTAssertEqualObjects(decoded.attachmentData, original.attachmentData);
    XCTAssertEqualObjects(decoded.contentType, original.contentType);
}

- (void)testSecureCoding_RoundTripWithBinaryData
{
    uint8_t binaryContent[] = {0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD};
    NSData *data = [NSData dataWithBytes:binaryContent length:6];
    
    BugSplatAttachment *original = [[BugSplatAttachment alloc] initWithFilename:@"binary.dat"
                                                                 attachmentData:data
                                                                    contentType:@"application/octet-stream"];
    
    // Encode
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:original
                                                 requiringSecureCoding:YES
                                                                 error:nil];
    
    // Decode
    BugSplatAttachment *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[BugSplatAttachment class]
                                                                    fromData:archivedData
                                                                       error:nil];
    
    XCTAssertEqualObjects(decoded.attachmentData, data);
}

- (void)testSecureCoding_RoundTripWithUnicodeFilename
{
    NSString *filename = @"日本語ファイル.txt";
    NSData *data = [@"Unicode content: 你好世界" dataUsingEncoding:NSUTF8StringEncoding];
    
    BugSplatAttachment *original = [[BugSplatAttachment alloc] initWithFilename:filename
                                                                 attachmentData:data
                                                                    contentType:@"text/plain; charset=utf-8"];
    
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:original
                                                 requiringSecureCoding:YES
                                                                 error:nil];
    
    BugSplatAttachment *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[BugSplatAttachment class]
                                                                    fromData:archivedData
                                                                       error:nil];
    
    XCTAssertEqualObjects(decoded.filename, filename);
    XCTAssertEqualObjects(decoded.attachmentData, data);
}

- (void)testSecureCoding_RoundTripWithEmptyData
{
    BugSplatAttachment *original = [[BugSplatAttachment alloc] initWithFilename:@"empty.txt"
                                                                 attachmentData:[NSData data]
                                                                    contentType:@"text/plain"];
    
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:original
                                                 requiringSecureCoding:YES
                                                                 error:nil];
    
    BugSplatAttachment *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[BugSplatAttachment class]
                                                                    fromData:archivedData
                                                                       error:nil];
    
    XCTAssertNotNil(decoded);
    XCTAssertEqual(decoded.attachmentData.length, 0);
}

- (void)testSecureCoding_RoundTripWithLargeData
{
    NSMutableData *largeData = [NSMutableData dataWithLength:100 * 1024]; // 100KB
    arc4random_buf(largeData.mutableBytes, largeData.length);
    
    BugSplatAttachment *original = [[BugSplatAttachment alloc] initWithFilename:@"large.bin"
                                                                 attachmentData:largeData
                                                                    contentType:@"application/octet-stream"];
    
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:original
                                                 requiringSecureCoding:YES
                                                                 error:nil];
    
    BugSplatAttachment *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[BugSplatAttachment class]
                                                                    fromData:archivedData
                                                                       error:nil];
    
    XCTAssertEqualObjects(decoded.attachmentData, largeData);
}

#pragma mark - Content Type Tests

- (void)testContentType_TextPlain
{
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:@"log.txt"
                                                                   attachmentData:[@"text" dataUsingEncoding:NSUTF8StringEncoding]
                                                                      contentType:@"text/plain"];
    XCTAssertEqualObjects(attachment.contentType, @"text/plain");
}

- (void)testContentType_ApplicationJson
{
    NSData *jsonData = [@"{\"key\": \"value\"}" dataUsingEncoding:NSUTF8StringEncoding];
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:@"data.json"
                                                                   attachmentData:jsonData
                                                                      contentType:@"application/json"];
    XCTAssertEqualObjects(attachment.contentType, @"application/json");
}

- (void)testContentType_ApplicationOctetStream
{
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:@"binary.dat"
                                                                   attachmentData:[NSData data]
                                                                      contentType:@"application/octet-stream"];
    XCTAssertEqualObjects(attachment.contentType, @"application/octet-stream");
}

- (void)testContentType_ApplicationXML
{
    NSData *xmlData = [@"<?xml version=\"1.0\"?><root/>" dataUsingEncoding:NSUTF8StringEncoding];
    BugSplatAttachment *attachment = [[BugSplatAttachment alloc] initWithFilename:@"config.xml"
                                                                   attachmentData:xmlData
                                                                      contentType:@"application/xml"];
    XCTAssertEqualObjects(attachment.contentType, @"application/xml");
}

@end
