//
//  BugSplatZipHelperTests.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "BugSplatZipHelper.h"
#import <zlib.h>

@interface BugSplatZipHelperTests : XCTestCase
@end

@implementation BugSplatZipHelperTests

#pragma mark - MD5 Hash Tests

- (void)testMD5Hash_EmptyData
{
    NSData *data = [NSData data];
    NSString *hash = [BugSplatZipHelper md5HashOfData:data];
    
    // MD5 of empty string is d41d8cd98f00b204e9800998ecf8427e
    XCTAssertEqualObjects(hash, @"d41d8cd98f00b204e9800998ecf8427e");
}

- (void)testMD5Hash_SimpleString
{
    NSData *data = [@"Hello, World!" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *hash = [BugSplatZipHelper md5HashOfData:data];
    
    // Known MD5 hash for "Hello, World!"
    XCTAssertEqualObjects(hash, @"65a8e27d8879283831b664bd8b7f0ad4");
}

- (void)testMD5Hash_ReturnsLowercaseHex
{
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *hash = [BugSplatZipHelper md5HashOfData:data];
    
    // Should be lowercase
    XCTAssertEqualObjects(hash, [hash lowercaseString]);
    
    // Should be 32 characters (128 bits as hex)
    XCTAssertEqual(hash.length, 32);
}

- (void)testMD5Hash_DifferentDataProducesDifferentHashes
{
    NSData *data1 = [@"test1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data2 = [@"test2" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSString *hash1 = [BugSplatZipHelper md5HashOfData:data1];
    NSString *hash2 = [BugSplatZipHelper md5HashOfData:data2];
    
    XCTAssertNotEqualObjects(hash1, hash2);
}

- (void)testMD5Hash_SameDataProducesSameHash
{
    NSData *data = [@"consistent" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSString *hash1 = [BugSplatZipHelper md5HashOfData:data];
    NSString *hash2 = [BugSplatZipHelper md5HashOfData:data];
    
    XCTAssertEqualObjects(hash1, hash2);
}

- (void)testMD5Hash_LargeData
{
    // Create 1MB of data
    NSMutableData *data = [NSMutableData dataWithLength:1024 * 1024];
    memset(data.mutableBytes, 'A', data.length);
    
    NSString *hash = [BugSplatZipHelper md5HashOfData:data];
    
    XCTAssertNotNil(hash);
    XCTAssertEqual(hash.length, 32);
}

#pragma mark - ZIP Entry Tests

- (void)testZipEntry_Creation
{
    NSData *data = [@"test content" dataUsingEncoding:NSUTF8StringEncoding];
    BugSplatZipEntry *entry = [BugSplatZipEntry entryWithFilename:@"test.txt" data:data];
    
    XCTAssertEqualObjects(entry.filename, @"test.txt");
    XCTAssertEqualObjects(entry.data, data);
}

#pragma mark - ZIP Data Tests

- (void)testZipData_CreatesValidZip
{
    NSData *content = [@"Hello, World!" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *zipData = [BugSplatZipHelper zipData:content withFilename:@"test.txt"];
    
    XCTAssertNotNil(zipData);
    XCTAssertGreaterThan(zipData.length, 0);
    
    // Verify ZIP magic number (PK signature)
    const uint8_t *bytes = zipData.bytes;
    XCTAssertEqual(bytes[0], 'P');
    XCTAssertEqual(bytes[1], 'K');
    XCTAssertEqual(bytes[2], 0x03);
    XCTAssertEqual(bytes[3], 0x04);
}

- (void)testZipData_ReturnsNilForNilData
{
    NSData *zipData = [BugSplatZipHelper zipData:nil withFilename:@"test.txt"];
    XCTAssertNil(zipData);
}

- (void)testZipData_ReturnsNilForNilFilename
{
    NSData *content = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *zipData = [BugSplatZipHelper zipData:content withFilename:nil];
    XCTAssertNil(zipData);
}

- (void)testZipData_ReturnsNilForEmptyFilename
{
    NSData *content = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *zipData = [BugSplatZipHelper zipData:content withFilename:@""];
    XCTAssertNil(zipData);
}

- (void)testZipData_ContainsFilename
{
    NSString *filename = @"myfile.txt";
    NSData *content = [@"content" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *zipData = [BugSplatZipHelper zipData:content withFilename:filename];
    
    // The filename should appear in the ZIP data (in local header and central directory)
    NSData *filenameData = [filename dataUsingEncoding:NSUTF8StringEncoding];
    NSRange range = [zipData rangeOfData:filenameData options:0 range:NSMakeRange(0, zipData.length)];
    
    XCTAssertNotEqual(range.location, NSNotFound);
}

- (void)testZipData_EmptyContent
{
    NSData *content = [NSData data];
    NSData *zipData = [BugSplatZipHelper zipData:content withFilename:@"empty.txt"];
    
    // Should still create a valid ZIP with an empty file
    XCTAssertNotNil(zipData);
    
    // Verify ZIP signature
    const uint8_t *bytes = zipData.bytes;
    XCTAssertEqual(bytes[0], 'P');
    XCTAssertEqual(bytes[1], 'K');
}

#pragma mark - ZIP Entries Tests

- (void)testZipEntries_MultipleFiles
{
    BugSplatZipEntry *entry1 = [BugSplatZipEntry entryWithFilename:@"file1.txt" 
                                                             data:[@"Content 1" dataUsingEncoding:NSUTF8StringEncoding]];
    BugSplatZipEntry *entry2 = [BugSplatZipEntry entryWithFilename:@"file2.txt" 
                                                             data:[@"Content 2" dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData *zipData = [BugSplatZipHelper zipEntries:@[entry1, entry2]];
    
    XCTAssertNotNil(zipData);
    
    // Both filenames should appear in the ZIP
    NSData *filename1Data = [@"file1.txt" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *filename2Data = [@"file2.txt" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSRange range1 = [zipData rangeOfData:filename1Data options:0 range:NSMakeRange(0, zipData.length)];
    NSRange range2 = [zipData rangeOfData:filename2Data options:0 range:NSMakeRange(0, zipData.length)];
    
    XCTAssertNotEqual(range1.location, NSNotFound);
    XCTAssertNotEqual(range2.location, NSNotFound);
}

- (void)testZipEntries_ReturnsNilForEmptyArray
{
    NSData *zipData = [BugSplatZipHelper zipEntries:@[]];
    XCTAssertNil(zipData);
}

- (void)testZipEntries_ReturnsNilForNilArray
{
    NSData *zipData = [BugSplatZipHelper zipEntries:nil];
    XCTAssertNil(zipData);
}

- (void)testZipEntries_SkipsInvalidEntries
{
    BugSplatZipEntry *validEntry = [BugSplatZipEntry entryWithFilename:@"valid.txt" 
                                                                 data:[@"content" dataUsingEncoding:NSUTF8StringEncoding]];
    BugSplatZipEntry *invalidEntry = [BugSplatZipEntry entryWithFilename:@"" data:[NSData data]];
    
    NSData *zipData = [BugSplatZipHelper zipEntries:@[validEntry, invalidEntry]];
    
    // Should create a ZIP with just the valid entry
    XCTAssertNotNil(zipData);
    
    NSData *validFilename = [@"valid.txt" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange range = [zipData rangeOfData:validFilename options:0 range:NSMakeRange(0, zipData.length)];
    XCTAssertNotEqual(range.location, NSNotFound);
}

- (void)testZipEntries_LargeFile
{
    // Create 100KB of data
    NSMutableData *largeData = [NSMutableData dataWithLength:100 * 1024];
    memset(largeData.mutableBytes, 'X', largeData.length);
    
    BugSplatZipEntry *entry = [BugSplatZipEntry entryWithFilename:@"large.bin" data:largeData];
    NSData *zipData = [BugSplatZipHelper zipEntries:@[entry]];
    
    XCTAssertNotNil(zipData);
    
    // Compressed data should be smaller than original (for repetitive data)
    XCTAssertLessThan(zipData.length, largeData.length);
}

- (void)testZipEntries_SpecialCharactersInFilename
{
    NSString *filename = @"file with spaces & special.txt";
    NSData *content = [@"content" dataUsingEncoding:NSUTF8StringEncoding];
    BugSplatZipEntry *entry = [BugSplatZipEntry entryWithFilename:filename data:content];
    
    NSData *zipData = [BugSplatZipHelper zipEntries:@[entry]];
    
    XCTAssertNotNil(zipData);
}

- (void)testZipEntries_UnicodeFilename
{
    NSString *filename = @"文件.txt";
    NSData *content = [@"content" dataUsingEncoding:NSUTF8StringEncoding];
    BugSplatZipEntry *entry = [BugSplatZipEntry entryWithFilename:filename data:content];
    
    NSData *zipData = [BugSplatZipHelper zipEntries:@[entry]];
    
    XCTAssertNotNil(zipData);
}

#pragma mark - ZIP Structure Validation Tests

- (void)testZipStructure_ContainsEndOfCentralDirectory
{
    NSData *content = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *zipData = [BugSplatZipHelper zipData:content withFilename:@"test.txt"];
    
    // End of Central Directory signature: 0x06054b50 (little endian: 50 4b 05 06)
    uint8_t endSignature[] = {0x50, 0x4b, 0x05, 0x06};
    NSData *signatureData = [NSData dataWithBytes:endSignature length:4];
    
    NSRange range = [zipData rangeOfData:signatureData options:0 range:NSMakeRange(0, zipData.length)];
    XCTAssertNotEqual(range.location, NSNotFound, @"ZIP should contain End of Central Directory signature");
}

- (void)testZipStructure_ContainsCentralDirectoryHeader
{
    NSData *content = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *zipData = [BugSplatZipHelper zipData:content withFilename:@"test.txt"];
    
    // Central Directory Header signature: 0x02014b50 (little endian: 50 4b 01 02)
    uint8_t cdSignature[] = {0x50, 0x4b, 0x01, 0x02};
    NSData *signatureData = [NSData dataWithBytes:cdSignature length:4];
    
    NSRange range = [zipData rangeOfData:signatureData options:0 range:NSMakeRange(0, zipData.length)];
    XCTAssertNotEqual(range.location, NSNotFound, @"ZIP should contain Central Directory Header signature");
}

#pragma mark - Compression Tests

- (void)testZipCompression_CompressesRepetitiveData
{
    // Create highly compressible data (repeated pattern)
    NSMutableString *repetitiveString = [NSMutableString string];
    for (int i = 0; i < 1000; i++) {
        [repetitiveString appendString:@"AAAAAAAAAA"];
    }
    NSData *content = [repetitiveString dataUsingEncoding:NSUTF8StringEncoding];
    
    NSData *zipData = [BugSplatZipHelper zipData:content withFilename:@"repetitive.txt"];
    
    XCTAssertNotNil(zipData);
    // Highly repetitive data should compress very well
    XCTAssertLessThan(zipData.length, content.length / 10);
}

- (void)testZipCompression_HandlesRandomData
{
    // Create random data (not very compressible)
    NSMutableData *randomData = [NSMutableData dataWithLength:1024];
    arc4random_buf(randomData.mutableBytes, randomData.length);
    
    NSData *zipData = [BugSplatZipHelper zipData:randomData withFilename:@"random.bin"];
    
    XCTAssertNotNil(zipData);
    // ZIP should still be created, even if compression doesn't help much
}

@end
