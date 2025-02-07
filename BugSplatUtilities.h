//
//  BugSplatUtilities.h
//
//  Copyright © 2025 BugSplat, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSArray (XMLArrayUtility)

/**
 * Given an array of tokenPairRange values, remove any tokenPairRange values that are
 * either fully contained within another range, or overlapping (partially contained) within another range.
 * return: validTokenPairRange in ascending range order by location.
 */
+ (NSArray<NSValue *> *)validTokenPairRanges:(NSArray<NSValue *> *)tokenPairRanges;

@end


@interface NSString (XMLStringUtility)

/**
 * Utility method to clean up special characters found in attribute or value strings
 *
 * NOTE: API based on macOS 10.3+ only API CFStringRef CFXMLCreateStringByEscapingEntities(CFAllocatorRef allocator, CFStringRef string, CFDictionaryRef entitiesDictionary)
 * This method considers CDATA, and Comments, but currently omits Processing Instructions when escaping is done on the receiver.
 */
- (NSString *)stringByEscapingXMLCharactersIgnoringCDataAndComments;


/**
 * Utility method to clean up special characters found in attribute or value strings
 *
 * NOTE: API based on macOS 10.3+ only API CFStringRef CFXMLCreateStringByEscapingEntities(CFAllocatorRef allocator, CFStringRef string, CFDictionaryRef entitiesDictionary)
 * This method does not consider CDATA, Comments, nor Processing Instructions when escaping is done on the receiver. See other methods to first identify these escape-exclusion ranges.
 */
- (NSString *)stringByEscapingSpecialXMLCharacters;

/**
 * Given a start token and end token pair, search receiver, returning array of NSValue objects containing NSRange of each pair found
 * Return Array will be empty if no pairs are found.
 * Error will be nil if no parsing errors occur.
 */
- (NSArray<NSValue *> *)tokenPairRangesForStartToken:(NSString *)startToken endToken:(NSString *)endToken error:(NSError **)error;

/**
 * Given a string, and an ascendingExclusionRanges sorted array (based on this receiver), escape the 5 special XML characters
 * within the receiver, taking care not to escape any characters within the exclusionRanges.
 */
- (NSString *)stringByXMLEscapingWithExclusionRanges:(NSArray<NSValue *> *)ascendingExclusionRanges;

@end
