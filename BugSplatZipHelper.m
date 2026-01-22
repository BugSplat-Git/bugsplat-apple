//
//  BugSplatZipHelper.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BugSplatZipHelper.h"
#import <zlib.h>
#import <CommonCrypto/CommonDigest.h>

// ZIP format constants
#define ZIP_LOCAL_FILE_HEADER_SIGNATURE     0x04034b50
#define ZIP_CENTRAL_DIR_HEADER_SIGNATURE    0x02014b50
#define ZIP_END_OF_CENTRAL_DIR_SIGNATURE    0x06054b50
#define ZIP_VERSION_MADE_BY                 0x0014  // Version 2.0
#define ZIP_VERSION_NEEDED                  0x0014  // Version 2.0
#define ZIP_COMPRESSION_DEFLATE             8
#define ZIP_COMPRESSION_STORE               0

@implementation BugSplatZipEntry

+ (instancetype)entryWithFilename:(NSString *)filename data:(NSData *)data
{
    BugSplatZipEntry *entry = [[BugSplatZipEntry alloc] init];
    entry.filename = filename;
    entry.data = data;
    return entry;
}

@end

@implementation BugSplatZipHelper

+ (nullable NSData *)zipData:(NSData *)data withFilename:(NSString *)filename
{
    if (!data || !filename || filename.length == 0) {
        return nil;
    }
    
    BugSplatZipEntry *entry = [BugSplatZipEntry entryWithFilename:filename data:data];
    return [self zipEntries:@[entry]];
}

+ (nullable NSData *)zipEntries:(NSArray<BugSplatZipEntry *> *)entries
{
    if (!entries || entries.count == 0) {
        return nil;
    }
    
    // Get current DOS date/time (same for all files)
    uint16_t dosTime, dosDate;
    [self getDOSTime:&dosTime date:&dosDate];
    
    NSMutableData *zipData = [NSMutableData data];
    NSMutableArray<NSNumber *> *localHeaderOffsets = [NSMutableArray array];
    NSMutableArray<NSData *> *compressedDataArray = [NSMutableArray array];
    NSMutableArray<NSNumber *> *crcValues = [NSMutableArray array];
    
    // === Write Local File Headers and File Data ===
    for (BugSplatZipEntry *entry in entries) {
        if (!entry.data || !entry.filename || entry.filename.length == 0) {
            continue;
        }
        
        NSData *filenameData = [entry.filename dataUsingEncoding:NSUTF8StringEncoding];
        if (!filenameData) {
            continue;
        }
        
        // Compress the data using deflate
        NSData *compressedData = [self deflateData:entry.data];
        if (!compressedData) {
            continue;
        }
        
        // Calculate CRC32 of uncompressed data
        uLong crc = crc32(0L, Z_NULL, 0);
        crc = crc32(crc, entry.data.bytes, (uInt)entry.data.length);
        
        // Store for central directory
        [localHeaderOffsets addObject:@(zipData.length)];
        [compressedDataArray addObject:compressedData];
        [crcValues addObject:@((uint32_t)crc)];
        
        // Write Local File Header
        uint32_t localHeaderSignature = ZIP_LOCAL_FILE_HEADER_SIGNATURE;
        uint16_t versionNeeded = ZIP_VERSION_NEEDED;
        uint16_t generalPurposeFlag = 0;
        uint16_t compressionMethod = ZIP_COMPRESSION_DEFLATE;
        uint32_t crc32Value = (uint32_t)crc;
        uint32_t compressedSize = (uint32_t)compressedData.length;
        uint32_t uncompressedSize = (uint32_t)entry.data.length;
        uint16_t filenameLength = (uint16_t)filenameData.length;
        uint16_t extraFieldLength = 0;
        
        [zipData appendBytes:&localHeaderSignature length:4];
        [zipData appendBytes:&versionNeeded length:2];
        [zipData appendBytes:&generalPurposeFlag length:2];
        [zipData appendBytes:&compressionMethod length:2];
        [zipData appendBytes:&dosTime length:2];
        [zipData appendBytes:&dosDate length:2];
        [zipData appendBytes:&crc32Value length:4];
        [zipData appendBytes:&compressedSize length:4];
        [zipData appendBytes:&uncompressedSize length:4];
        [zipData appendBytes:&filenameLength length:2];
        [zipData appendBytes:&extraFieldLength length:2];
        [zipData appendData:filenameData];
        
        // Write File Data
        [zipData appendData:compressedData];
    }
    
    if (localHeaderOffsets.count == 0) {
        return nil;
    }
    
    // === Write Central Directory Headers ===
    uint32_t centralDirOffset = (uint32_t)zipData.length;
    
    NSUInteger validEntryIndex = 0;
    for (BugSplatZipEntry *entry in entries) {
        if (!entry.data || !entry.filename || entry.filename.length == 0) {
            continue;
        }
        
        NSData *filenameData = [entry.filename dataUsingEncoding:NSUTF8StringEncoding];
        if (!filenameData) {
            continue;
        }
        
        NSData *compressedData = compressedDataArray[validEntryIndex];
        uint32_t crc32Value = [crcValues[validEntryIndex] unsignedIntValue];
        uint32_t localHeaderOffset = [localHeaderOffsets[validEntryIndex] unsignedIntValue];
        
        uint32_t centralHeaderSignature = ZIP_CENTRAL_DIR_HEADER_SIGNATURE;
        uint16_t versionMadeBy = ZIP_VERSION_MADE_BY;
        uint16_t versionNeeded = ZIP_VERSION_NEEDED;
        uint16_t generalPurposeFlag = 0;
        uint16_t compressionMethod = ZIP_COMPRESSION_DEFLATE;
        uint32_t compressedSize = (uint32_t)compressedData.length;
        uint32_t uncompressedSize = (uint32_t)entry.data.length;
        uint16_t filenameLength = (uint16_t)filenameData.length;
        uint16_t extraFieldLength = 0;
        uint16_t fileCommentLength = 0;
        uint16_t diskNumberStart = 0;
        uint16_t internalFileAttributes = 0;
        uint32_t externalFileAttributes = 0;
        
        [zipData appendBytes:&centralHeaderSignature length:4];
        [zipData appendBytes:&versionMadeBy length:2];
        [zipData appendBytes:&versionNeeded length:2];
        [zipData appendBytes:&generalPurposeFlag length:2];
        [zipData appendBytes:&compressionMethod length:2];
        [zipData appendBytes:&dosTime length:2];
        [zipData appendBytes:&dosDate length:2];
        [zipData appendBytes:&crc32Value length:4];
        [zipData appendBytes:&compressedSize length:4];
        [zipData appendBytes:&uncompressedSize length:4];
        [zipData appendBytes:&filenameLength length:2];
        [zipData appendBytes:&extraFieldLength length:2];
        [zipData appendBytes:&fileCommentLength length:2];
        [zipData appendBytes:&diskNumberStart length:2];
        [zipData appendBytes:&internalFileAttributes length:2];
        [zipData appendBytes:&externalFileAttributes length:4];
        [zipData appendBytes:&localHeaderOffset length:4];
        [zipData appendData:filenameData];
        
        validEntryIndex++;
    }
    
    // === End of Central Directory Record ===
    uint32_t centralDirSize = (uint32_t)zipData.length - centralDirOffset;
    uint16_t numEntries = (uint16_t)localHeaderOffsets.count;
    
    uint32_t endOfCentralDirSignature = ZIP_END_OF_CENTRAL_DIR_SIGNATURE;
    uint16_t diskNumber = 0;
    uint16_t diskNumberWithCentralDir = 0;
    uint16_t commentLength = 0;
    
    [zipData appendBytes:&endOfCentralDirSignature length:4];
    [zipData appendBytes:&diskNumber length:2];
    [zipData appendBytes:&diskNumberWithCentralDir length:2];
    [zipData appendBytes:&numEntries length:2];
    [zipData appendBytes:&numEntries length:2];
    [zipData appendBytes:&centralDirSize length:4];
    [zipData appendBytes:&centralDirOffset length:4];
    [zipData appendBytes:&commentLength length:2];
    
    return [zipData copy];
}

+ (nullable NSData *)deflateData:(NSData *)data
{
    if (data.length == 0) {
        return [NSData data];
    }
    
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    
    // Use negative window bits for raw deflate (no zlib header)
    int result = deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
    if (result != Z_OK) {
        return nil;
    }
    
    stream.next_in = (Bytef *)data.bytes;
    stream.avail_in = (uInt)data.length;
    
    // Allocate output buffer (worst case: slightly larger than input)
    NSMutableData *compressedData = [NSMutableData dataWithLength:data.length + 1024];
    stream.next_out = (Bytef *)compressedData.mutableBytes;
    stream.avail_out = (uInt)compressedData.length;
    
    result = deflate(&stream, Z_FINISH);
    deflateEnd(&stream);
    
    if (result != Z_STREAM_END) {
        return nil;
    }
    
    [compressedData setLength:stream.total_out];
    return [compressedData copy];
}

+ (void)getDOSTime:(uint16_t *)dosTime date:(uint16_t *)dosDate
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                                                         NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                               fromDate:[NSDate date]];
    
    // DOS time: bits 0-4 = seconds/2, bits 5-10 = minute, bits 11-15 = hour
    *dosTime = (uint16_t)(((components.second / 2) & 0x1F) |
                          ((components.minute & 0x3F) << 5) |
                          ((components.hour & 0x1F) << 11));
    
    // DOS date: bits 0-4 = day, bits 5-8 = month, bits 9-15 = year-1980
    *dosDate = (uint16_t)((components.day & 0x1F) |
                          ((components.month & 0x0F) << 5) |
                          (((components.year - 1980) & 0x7F) << 9));
}

+ (NSString *)md5HashOfData:(NSData *)data
{
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    // MD5 is required by the BugSplat API for commit verification
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
#pragma clang diagnostic pop
    
    NSMutableString *hashString = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hashString appendFormat:@"%02x", digest[i]];
    }
    
    return [hashString copy];
}

@end
