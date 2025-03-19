//
//  BugSplatUtilities.h
//
//  Copyright © BugSplat, LLC. All rights reserved.
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

/**
 * Validate NSString as an XML entity name (including element name, attribute names), return YES if it is a valid XML entity.
 * In XML, the rules for naming entities (which include element names, attribute names, and other identifiers) are defined by the XML specification. Here are the key rules for valid XML names:
 * 1. Start Character: An XML name must start with a letter (either uppercase or lowercase) or an underscore (_). It cannot start with a digit or any other character.
 * 2. Subsequent Characters: After the first character, the name can contain:
 *    Letters (A-Z, a-z)
 *    Digits (0-9)
 *    Hyphens (-)
 *    Underscores (_)
 *    Periods (.)
 *    Colons (:)
 *    Combining characters
 *    Extender characters
 * 3. Length: There is no specific limit on the length of an XML name, but it should be reasonable for practical purposes.
 * 4. Case Sensitivity: XML names are case-sensitive. For example, <Tag> and <tag> would be considered different names.
 * 5. Forbidden Characters: The following characters are not allowed in XML names:
 *    Spaces
 *    Special characters (like @, #, $, etc.)
 *    Punctuation marks (except for the allowed ones mentioned above)
 *    Control characters (ASCII values 0-31)
 * 6. Reserved Names: Certain names are reserved in XML, such as those starting with "xml" (e.g., xml, xmlns, etc.), which are used for XML namespaces.
 */
- (BOOL)isValidXMLEntity;
@end
