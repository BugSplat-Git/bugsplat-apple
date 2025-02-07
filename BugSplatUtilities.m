//
//  BugSplatUtilities.m
//
//  Copyright © 2025 BugSplat, LLC. All rights reserved.
//

#import "BugSplatUtilities.h"


@implementation NSArray (XMLArrayUtility)

/**
 * Given an array of tokenPairRange values, remove any tokenPairRange values that are
 * either fully contained within another range, or overlapping (partially contained) within another range.
 * - return: validTokenPairRange in least to greatest order.
 */
+ (NSArray<NSValue *> *)validTokenPairRanges:(NSArray<NSValue *> *)tokenPairRanges
{
    // sanity check if there are 1 or less ranges to begin with, exit early
    if (tokenPairRanges.count <= 1) {
        return tokenPairRanges;
    }

    // first sort the input tokenPairRanges by ascending range.location order
    NSArray<NSValue *> *sortedTokenPairRanges = [tokenPairRanges sortedArrayUsingComparator:^NSComparisonResult(NSValue * _Nonnull rangeValue1, NSValue * _Nonnull rangeValue2) {
        if (rangeValue1.rangeValue.location < rangeValue2.rangeValue.location) {
            return NSOrderedAscending;
        } else if (rangeValue1.rangeValue.location > rangeValue2.rangeValue.location) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }];

    // given at least 2 ranges in sortedTokenPairRanges
    // remove first range since this is valid since the location is not bounded by any other range

    // given sorted array of NSValue Ranges, remove any contained, partially contained/overlapping ranges.
    NSMutableArray<NSValue *> *sortedRanges = [NSMutableArray arrayWithArray:sortedTokenPairRanges];

    NSValue *validRange = [sortedRanges firstObject];
    [sortedRanges removeObjectAtIndex:0];
    NSMutableArray<NSValue *> *validRanges = [NSMutableArray arrayWithArray:@[validRange]];

    // loop over sortedRanges comparing to validRange looking for containment or overlaps
    do {
        NSValue *checkRange = [sortedRanges firstObject];
        [sortedRanges removeObjectAtIndex:0];
        if (validRange.rangeValue.location + validRange.rangeValue.length <= checkRange.rangeValue.location) {
            [validRanges addObject:checkRange];
            validRange = checkRange; // this becomes the next valid range to use for containment checking with remaining sortedRanges
        }

    } while (sortedRanges.count > 0);

    return [validRanges copy];
}

@end


@implementation NSString (XMLStringUtility)

/**
 * Utility method to clean up special characters found in attribute or value strings
 *
 * NOTE: API based on macOS 10.3+ only API CFStringRef CFXMLCreateStringByEscapingEntities(CFAllocatorRef allocator, CFStringRef string, CFDictionaryRef entitiesDictionary)
 * This method considers CDATA, and Comments, but currently omits Processing Instructions when escaping is done on the receiver.
 */
- (NSString *)stringByEscapingXMLCharactersIgnoringCDataAndComments
{
    NSError *error = nil;
    NSArray<NSValue *> *cDataTokenPairRanges = [self tokenPairRangesForStartToken:@"<![CDATA[" endToken:@"]]>" error:&error];
    NSLog(@"CDATA token pair ranges found: %ld", cDataTokenPairRanges.count);
    if (error != nil) {
        NSLog(@"CDATA parsing error was found!");
    }

    error = nil; // reset
    // does not check for invalid use of -- within the comment pair, nor for invalid ending --->, nor for <--- invalid starts
    NSArray<NSValue *> *commentTokenPairRanges = [self tokenPairRangesForStartToken:@"<!--" endToken:@"-->" error:&error];
    NSLog(@"Comment token pair ranges found: %ld", commentTokenPairRanges.count);
    if (error != nil) {
        NSLog(@"XML Comment parsing error was found!");
    }

    // processing instructions not currently supported
    // NSArray<NSValue *> *processingInstructionsTokenPairRanges = [testString tokenPairRangesForStartToken:@"<?somecommand " endToken:@"?>" error:&error];

    // sum of CDATA and COMMENT ranges
    NSMutableArray<NSValue *> *exclusionRanges = [NSMutableArray arrayWithArray:cDataTokenPairRanges];
    [exclusionRanges addObjectsFromArray:commentTokenPairRanges];

    NSArray<NSValue *> *validTokenPairRanges = [NSArray validTokenPairRanges:exclusionRanges];

    NSLog(@"valid token pair ranges found: %ld", validTokenPairRanges.count);
    for (NSValue *rangeValue in validTokenPairRanges) {
        NSLog(@"range found: loc: %lu, len: %lu", rangeValue.rangeValue.location, rangeValue.rangeValue.length);
    }

    NSString *escapedString = [self stringByXMLEscapingWithExclusionRanges:validTokenPairRanges];
    NSLog(@"before escape: %@", self);
    NSLog(@"after escape:  %@", escapedString);

    return escapedString;
}

/**
 * Utility method to clean up special characters found in attribute or value strings
 *
 * NOTE: API based on macOS 10.3+ only API CFStringRef CFXMLCreateStringByEscapingEntities(CFAllocatorRef allocator, CFStringRef string, CFDictionaryRef entitiesDictionary)
 * This method does not consider CDATA, Comments, nor Processing Instructions when escaping is done on the receiver. See other methods to first identify these escape-exclusion ranges.
 */
- (NSString *)stringByEscapingSpecialXMLCharacters
{
    // Standard XML characters to escape
    // See: https://stackoverflow.com/questions/1091945/what-characters-do-i-need-to-escape-in-xml-documents
    NSMutableDictionary<NSString *, NSString *> *escapingDictionary = [NSMutableDictionary dictionaryWithObjects:@[@"&quot;", @"&apos;", @"&lt;", @"&gt;", @"&amp;"]
                                                                                           forKeys:@[@"\"", @"'", @"<", @">", @"&"]];

    // because '&' is a special character and is also used to escape all the special characters, replace & first before the others
    // special attention must be used to only escape '&' if it is NOT already in the form of an escape code (a key in escaping dictionary)

    // find any existing escaped sequence ranges
    NSMutableArray<NSValue *> *existingEscapedRanges = [NSMutableArray new];

    // for each escapeSequence, find all the ranges within this string
    BOOL isEndReached = NO;
    for (NSString *escapeSequence in escapingDictionary.objectEnumerator) {
        NSRange rangeOfEscapeSequence;
        NSUInteger location = 0;
        do {
            rangeOfEscapeSequence = [self rangeOfString:escapeSequence options:NSCaseInsensitiveSearch range:NSMakeRange(location, self.length - location)];
            if (rangeOfEscapeSequence.length != 0)
            {
                [existingEscapedRanges addObject:[NSValue valueWithRange:rangeOfEscapeSequence]];

                // move location to just after escapeSequence
                location = rangeOfEscapeSequence.location + rangeOfEscapeSequence.length;

                // check if at or past end of string
                if (location >= self.length)
                {
                    isEndReached = YES;
                }
            }
        } while (rangeOfEscapeSequence.length != 0 && !isEndReached);
    }

    // find all ranges of '&' within string
    NSMutableArray<NSValue *> *ampersandRanges = [NSMutableArray new];
    [self enumerateSubstringsInRange:NSMakeRange(0, self.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString * _Nullable substring, NSRange substringRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
        if ([substring isEqualToString:@"&"])
        {
            [ampersandRanges addObject:[NSValue valueWithRange:substringRange]];
        }
    }];

    // remove any ampersandRanges which correspond to a range within existingEscapedRanges
    for (NSValue *escapedRangeValue in existingEscapedRanges) {
        NSValue *removeValue = [NSValue valueWithRange:NSMakeRange([escapedRangeValue rangeValue].location, 1)]; // length 1 for range of '&'
        [ampersandRanges removeObject:removeValue];
    }

    // in reverse order to avoid incorrect range values after replacement, replace '&' with '&amp;'
    NSString *escapedOutput = self;
    for (NSValue *rangeValue in [ampersandRanges reverseObjectEnumerator]) {
        escapedOutput = [escapedOutput stringByReplacingOccurrencesOfString:@"&"
                                                                 withString:@"&amp;"
                                                                    options:NSCaseInsensitiveSearch
                                                                      range:[rangeValue rangeValue]];
    }

    // '&' has been replaced with '&amp;' but only when '&' was not part of an escape sequence
    // remove '&' key/value pair since it was already carefully escaped above
    escapingDictionary[@"&"] = nil;

    // now, escape the other special characters
    for (NSString *target in escapingDictionary.allKeys) {
        NSString *replacement = escapingDictionary[target];
        escapedOutput = [escapedOutput stringByReplacingOccurrencesOfString:target withString:replacement];
    }

    return escapedOutput;
}

/**
 * Given a string, and an ascendingExclusionRanges sorted array (based on this receiver), escape the 5 special XML characters
 * within the receiver, taking care not to escape any characters within the exclusionRanges.
 */
- (NSString *)stringByXMLEscapingWithExclusionRanges:(NSArray<NSValue *> *)ascendingExclusionRanges
{
    // sanity check, if no ascendingExclusionRanges, just escape the whole string and return
    if (ascendingExclusionRanges == nil || [ascendingExclusionRanges count] == 0) { // no exclusion ranges
        return [self stringByEscapingSpecialXMLCharacters];
    }

    // divide receiver into substrings, escaping substrings outside of the exclusion ranges
    NSUInteger substringLoc = 0;

    // carry results here
    NSMutableString *escapedString = [NSMutableString new];

    for (NSValue *exclusionRange in ascendingExclusionRanges) {

        if (exclusionRange.rangeValue.location - substringLoc > 0) { // if a substring before exclusionRange, escape and add it first
            NSUInteger substringLength = exclusionRange.rangeValue.location - substringLoc;
            NSString *substring = [self substringWithRange:NSMakeRange(substringLoc, substringLength)];
            [escapedString appendString:[substring stringByEscapingSpecialXMLCharacters]];
        }

        // add exclusionString without escaping
        NSString *exclusionString = [self substringWithRange:NSMakeRange(exclusionRange.rangeValue.location, exclusionRange.rangeValue.length)];
        [escapedString appendString:exclusionString];

        // adjust substringLoc to just after exclusionRange
        substringLoc = exclusionRange.rangeValue.location + exclusionRange.rangeValue.length;
    }

    // any remaining substring after last exclusionRange?
    if (self.length - substringLoc > 0) {
        NSUInteger substringLength = self.length - substringLoc;
        NSString *substring = [self substringWithRange:NSMakeRange(substringLoc, substringLength)];
        [escapedString appendString:[substring stringByEscapingSpecialXMLCharacters]];
    }

    return [escapedString copy];
}

/**
 * Given a start token and end token pair, search receiver, returning array of NSValue objects containing NSRange of each pair found
 * Return Array will be empty if no pairs are found.
 * Error will be nil if no parsing errors occur.
 */
- (NSArray<NSValue *> *)tokenPairRangesForStartToken:(NSString *)startToken endToken:(NSString *)endToken error:(NSError **)error
{
    // Standard XML characters to escape
    // See: https://stackoverflow.com/questions/1091945/what-characters-do-i-need-to-escape-in-xml-documents
    //
    // <?PITarget excluding XML or xml should be taken literally as processing instructions for an application ?>
    // <!-- characters to be taken literally -->
    // <![CDATA[ ...characters to be taken literally... ]]>

    NSMutableArray<NSValue *> *tokenPairValueRanges = [NSMutableArray new];
    BOOL endOfStringReached = NO;
    NSUInteger startTokenSearchRangeLocation = 0;
    NSUInteger startTokenSearchRangeLength = self.length;

    // search for start and end token pairs until end of string is reached
    do {
        if (startToken.length <= startTokenSearchRangeLength) {
            NSRange startTokenSearchRange = NSMakeRange(startTokenSearchRangeLocation, self.length - startTokenSearchRangeLocation);
            NSRange startTokenRange = [self rangeOfString:startToken options:NSLiteralSearch range:startTokenSearchRange];

            if (startTokenRange.length != 0) { // start token found, now look for end token


                NSLog(@"startToken %@ found at Range: loc: %lu, len: %lu", startToken, startTokenRange.location, startTokenRange.length);

                NSUInteger endTokenSearchRangeLocation = startTokenRange.location + startTokenRange.length;
                NSUInteger endTokenSearchRangeLength = self.length - endTokenSearchRangeLocation;

                // check if enough length is left to find end token
                if (endToken.length <= endTokenSearchRangeLength) {
                    // search for end token
                    NSRange endTokenSearchRange = NSMakeRange(endTokenSearchRangeLocation, endTokenSearchRangeLength);
                    NSRange endTokenRange = [self rangeOfString:endToken options:NSLiteralSearch range:endTokenSearchRange];

                    if (endTokenRange.length != 0) { // end token found

                        NSLog(@"endToken %@ found at Range: loc: %lu, len: %lu", endToken, endTokenRange.location, endTokenRange.length);

                        // token pair range begins at startRange.location and ends at endRange.location + endRange.length
                        NSRange tokenPairRange = NSMakeRange(startTokenRange.location, endTokenRange.location - startTokenRange.location + endTokenRange.length);
                        [tokenPairValueRanges addObject:[NSValue valueWithRange:tokenPairRange]];

                        // adjust startTokenSearchRangeLocation and startTokenSearchRangeLength
                        startTokenSearchRangeLocation = endTokenRange.location + endTokenRange.length;
                        startTokenSearchRangeLength = self.length - startTokenSearchRangeLocation;

                    } else { // invalid string - missing expected endToken
                        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:nil];
                    }
                } else { // invalid string - not enough length remaining to find end token
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:2 userInfo:nil];
                }
            } else {
                // no start token found - not an error condition
                endOfStringReached = YES;
            }
        } else {
            endOfStringReached = YES;
        }

    } while (*error == nil && !endOfStringReached);

    return [tokenPairValueRanges copy];
}

@end
