//
//  BugSplatZipHelper.h
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents a file entry to be added to a ZIP archive.
 */
@interface BugSplatZipEntry : NSObject

@property (nonatomic, copy) NSString *filename;
@property (nonatomic, strong) NSData *data;

+ (instancetype)entryWithFilename:(NSString *)filename data:(NSData *)data;

@end

/**
 * Helper class for creating ZIP archives and computing MD5 hashes.
 * Uses system zlib library for compression and CommonCrypto for hashing.
 */
@interface BugSplatZipHelper : NSObject

/**
 * Creates a ZIP archive containing a single file.
 *
 * @param data The data to compress and add to the archive.
 * @param filename The filename to use inside the ZIP archive.
 * @return NSData containing the complete ZIP archive, or nil on failure.
 */
+ (nullable NSData *)zipData:(NSData *)data withFilename:(NSString *)filename;

/**
 * Creates a ZIP archive containing multiple files.
 *
 * @param entries An array of BugSplatZipEntry objects representing files to include.
 * @return NSData containing the complete ZIP archive, or nil on failure.
 */
+ (nullable NSData *)zipEntries:(NSArray<BugSplatZipEntry *> *)entries;

/**
 * Calculates the MD5 hash of the given data.
 *
 * @param data The data to hash.
 * @return A lowercase hexadecimal string representation of the MD5 hash.
 */
+ (NSString *)md5HashOfData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
