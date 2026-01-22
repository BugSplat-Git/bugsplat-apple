//
//  BugSplatUtilitiesTests.m
//  BugSplatTests
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "BugSplatUtilities.h"

@interface BugSplatUtilitiesTests : XCTestCase
@end

@implementation BugSplatUtilitiesTests

#pragma mark - isValidXMLEntity Tests

- (void)testIsValidXMLEntity_ValidSimpleName
{
    XCTAssertTrue([@"name" isValidXMLEntity]);
    XCTAssertTrue([@"Name" isValidXMLEntity]);
    XCTAssertTrue([@"NAME" isValidXMLEntity]);
}

- (void)testIsValidXMLEntity_ValidWithUnderscore
{
    XCTAssertTrue([@"_name" isValidXMLEntity]);
    XCTAssertTrue([@"my_name" isValidXMLEntity]);
    XCTAssertTrue([@"_" isValidXMLEntity]);
}

- (void)testIsValidXMLEntity_ValidWithNumbers
{
    XCTAssertTrue([@"name1" isValidXMLEntity]);
    XCTAssertTrue([@"name123" isValidXMLEntity]);
    XCTAssertTrue([@"_123" isValidXMLEntity]);
}

- (void)testIsValidXMLEntity_ValidWithHyphensAndPeriods
{
    XCTAssertTrue([@"my-name" isValidXMLEntity]);
    XCTAssertTrue([@"my.name" isValidXMLEntity]);
    XCTAssertTrue([@"my-name.value" isValidXMLEntity]);
}

- (void)testIsValidXMLEntity_ValidWithColons
{
    XCTAssertTrue([@"ns:name" isValidXMLEntity]);
    XCTAssertTrue([@"xml:lang" isValidXMLEntity]);
}

- (void)testIsValidXMLEntity_InvalidEmpty
{
    XCTAssertFalse([@"" isValidXMLEntity]);
}

- (void)testIsValidXMLEntity_InvalidStartsWithNumber
{
    XCTAssertFalse([@"1name" isValidXMLEntity]);
    XCTAssertFalse([@"123" isValidXMLEntity]);
}

- (void)testIsValidXMLEntity_InvalidStartsWithHyphen
{
    XCTAssertFalse([@"-name" isValidXMLEntity]);
}

- (void)testIsValidXMLEntity_InvalidStartsWithPeriod
{
    XCTAssertFalse([@".name" isValidXMLEntity]);
}

- (void)testIsValidXMLEntity_InvalidContainsSpace
{
    XCTAssertFalse([@"my name" isValidXMLEntity]);
    XCTAssertFalse([@"name " isValidXMLEntity]);
    XCTAssertFalse([@" name" isValidXMLEntity]);
}

- (void)testIsValidXMLEntity_InvalidSpecialCharacters
{
    XCTAssertFalse([@"name@value" isValidXMLEntity]);
    XCTAssertFalse([@"name#value" isValidXMLEntity]);
    XCTAssertFalse([@"name$value" isValidXMLEntity]);
    XCTAssertFalse([@"name%value" isValidXMLEntity]);
    XCTAssertFalse([@"name&value" isValidXMLEntity]);
    XCTAssertFalse([@"name<value" isValidXMLEntity]);
    XCTAssertFalse([@"name>value" isValidXMLEntity]);
}

#pragma mark - stringByEscapingSpecialXMLCharacters Tests

- (void)testEscapingXMLCharacters_NoEscapingNeeded
{
    NSString *input = @"Hello World";
    NSString *result = [input stringByEscapingSpecialXMLCharacters];
    XCTAssertEqualObjects(result, @"Hello World");
}

- (void)testEscapingXMLCharacters_EscapesAmpersand
{
    NSString *input = @"Tom & Jerry";
    NSString *result = [input stringByEscapingSpecialXMLCharacters];
    XCTAssertEqualObjects(result, @"Tom &amp; Jerry");
}

- (void)testEscapingXMLCharacters_EscapesLessThan
{
    NSString *input = @"a < b";
    NSString *result = [input stringByEscapingSpecialXMLCharacters];
    XCTAssertEqualObjects(result, @"a &lt; b");
}

- (void)testEscapingXMLCharacters_EscapesGreaterThan
{
    NSString *input = @"a > b";
    NSString *result = [input stringByEscapingSpecialXMLCharacters];
    XCTAssertEqualObjects(result, @"a &gt; b");
}

- (void)testEscapingXMLCharacters_EscapesDoubleQuote
{
    NSString *input = @"He said \"Hello\"";
    NSString *result = [input stringByEscapingSpecialXMLCharacters];
    XCTAssertEqualObjects(result, @"He said &quot;Hello&quot;");
}

- (void)testEscapingXMLCharacters_EscapesSingleQuote
{
    NSString *input = @"It's a test";
    NSString *result = [input stringByEscapingSpecialXMLCharacters];
    XCTAssertEqualObjects(result, @"It&apos;s a test");
}

- (void)testEscapingXMLCharacters_EscapesMultipleCharacters
{
    NSString *input = @"<tag attr=\"value\">Tom & Jerry's</tag>";
    NSString *result = [input stringByEscapingSpecialXMLCharacters];
    XCTAssertEqualObjects(result, @"&lt;tag attr=&quot;value&quot;&gt;Tom &amp; Jerry&apos;s&lt;/tag&gt;");
}

- (void)testEscapingXMLCharacters_PreservesExistingEscapeSequences
{
    NSString *input = @"Already &amp; escaped";
    NSString *result = [input stringByEscapingSpecialXMLCharacters];
    // Should not double-escape
    XCTAssertEqualObjects(result, @"Already &amp; escaped");
}

- (void)testEscapingXMLCharacters_PreservesAllEscapeSequences
{
    NSString *input = @"&lt; &gt; &amp; &quot; &apos;";
    NSString *result = [input stringByEscapingSpecialXMLCharacters];
    XCTAssertEqualObjects(result, @"&lt; &gt; &amp; &quot; &apos;");
}

- (void)testEscapingXMLCharacters_EmptyString
{
    NSString *input = @"";
    NSString *result = [input stringByEscapingSpecialXMLCharacters];
    XCTAssertEqualObjects(result, @"");
}

#pragma mark - stringByEscapingXMLCharactersIgnoringCDataAndComments Tests

- (void)testEscapingIgnoringCData_PreservesCDataContent
{
    NSString *input = @"Before <![CDATA[<special & content>]]> After";
    NSString *result = [input stringByEscapingXMLCharactersIgnoringCDataAndComments];
    XCTAssertEqualObjects(result, @"Before <![CDATA[<special & content>]]> After");
}

- (void)testEscapingIgnoringCData_EscapesOutsideCData
{
    NSString *input = @"Tom & Jerry <![CDATA[<inside>]]> More & stuff";
    NSString *result = [input stringByEscapingXMLCharactersIgnoringCDataAndComments];
    XCTAssertEqualObjects(result, @"Tom &amp; Jerry <![CDATA[<inside>]]> More &amp; stuff");
}

- (void)testEscapingIgnoringComments_PreservesCommentContent
{
    NSString *input = @"Before <!-- <special & content> --> After";
    NSString *result = [input stringByEscapingXMLCharactersIgnoringCDataAndComments];
    XCTAssertEqualObjects(result, @"Before <!-- <special & content> --> After");
}

- (void)testEscapingIgnoringComments_EscapesOutsideComments
{
    NSString *input = @"Tom & Jerry <!-- inside --> More & stuff";
    NSString *result = [input stringByEscapingXMLCharactersIgnoringCDataAndComments];
    XCTAssertEqualObjects(result, @"Tom &amp; Jerry <!-- inside --> More &amp; stuff");
}

- (void)testEscapingIgnoringBoth_MixedCDataAndComments
{
    NSString *input = @"A & B <![CDATA[<c>]]> D & E <!-- comment --> F & G";
    NSString *result = [input stringByEscapingXMLCharactersIgnoringCDataAndComments];
    XCTAssertEqualObjects(result, @"A &amp; B <![CDATA[<c>]]> D &amp; E <!-- comment --> F &amp; G");
}

#pragma mark - tokenPairRangesForStartToken:endToken:error: Tests

- (void)testTokenPairRanges_FindsSinglePair
{
    NSString *input = @"Before <![CDATA[content]]> After";
    NSError *error = nil;
    NSArray<NSValue *> *ranges = [input tokenPairRangesForStartToken:@"<![CDATA[" endToken:@"]]>" error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(ranges.count, 1);
    
    NSRange range = ranges[0].rangeValue;
    NSString *extracted = [input substringWithRange:range];
    XCTAssertEqualObjects(extracted, @"<![CDATA[content]]>");
}

- (void)testTokenPairRanges_FindsMultiplePairs
{
    NSString *input = @"<![CDATA[one]]> middle <![CDATA[two]]>";
    NSError *error = nil;
    NSArray<NSValue *> *ranges = [input tokenPairRangesForStartToken:@"<![CDATA[" endToken:@"]]>" error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(ranges.count, 2);
}

- (void)testTokenPairRanges_FindsComments
{
    NSString *input = @"Before <!-- comment --> After";
    NSError *error = nil;
    NSArray<NSValue *> *ranges = [input tokenPairRangesForStartToken:@"<!--" endToken:@"-->" error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(ranges.count, 1);
    
    NSRange range = ranges[0].rangeValue;
    NSString *extracted = [input substringWithRange:range];
    XCTAssertEqualObjects(extracted, @"<!-- comment -->");
}

- (void)testTokenPairRanges_ReturnsEmptyForNoMatches
{
    NSString *input = @"No special tokens here";
    NSError *error = nil;
    NSArray<NSValue *> *ranges = [input tokenPairRangesForStartToken:@"<![CDATA[" endToken:@"]]>" error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(ranges.count, 0);
}

- (void)testTokenPairRanges_ErrorOnUnmatchedStartToken
{
    NSString *input = @"Before <![CDATA[ missing end";
    NSError *error = nil;
    NSArray<NSValue *> *ranges = [input tokenPairRangesForStartToken:@"<![CDATA[" endToken:@"]]>" error:&error];
    
    XCTAssertNotNil(error);
    // Partial results may be returned, but error should be set
}

#pragma mark - validTokenPairRanges Tests

- (void)testValidTokenPairRanges_RemovesOverlapping
{
    // Create ranges where second is contained within first
    NSValue *range1 = [NSValue valueWithRange:NSMakeRange(0, 20)];
    NSValue *range2 = [NSValue valueWithRange:NSMakeRange(5, 10)]; // Contained within range1
    
    NSArray *result = [NSArray validTokenPairRanges:@[range1, range2]];
    
    XCTAssertEqual(result.count, 1);
    XCTAssertEqualObjects(result[0], range1);
}

- (void)testValidTokenPairRanges_KeepsNonOverlapping
{
    NSValue *range1 = [NSValue valueWithRange:NSMakeRange(0, 10)];
    NSValue *range2 = [NSValue valueWithRange:NSMakeRange(15, 10)];
    
    NSArray *result = [NSArray validTokenPairRanges:@[range1, range2]];
    
    XCTAssertEqual(result.count, 2);
}

- (void)testValidTokenPairRanges_SortsResults
{
    NSValue *range1 = [NSValue valueWithRange:NSMakeRange(20, 10)];
    NSValue *range2 = [NSValue valueWithRange:NSMakeRange(0, 10)];
    
    NSArray *result = [NSArray validTokenPairRanges:@[range1, range2]];
    
    XCTAssertEqual(result.count, 2);
    XCTAssertEqual([result[0] rangeValue].location, 0);
    XCTAssertEqual([result[1] rangeValue].location, 20);
}

- (void)testValidTokenPairRanges_HandlesEmptyArray
{
    NSArray *result = [NSArray validTokenPairRanges:@[]];
    XCTAssertEqual(result.count, 0);
}

- (void)testValidTokenPairRanges_HandlesSingleRange
{
    NSValue *range = [NSValue valueWithRange:NSMakeRange(0, 10)];
    NSArray *result = [NSArray validTokenPairRanges:@[range]];
    
    XCTAssertEqual(result.count, 1);
    XCTAssertEqualObjects(result[0], range);
}

- (void)testValidTokenPairRanges_RemovesPartiallyOverlapping
{
    NSValue *range1 = [NSValue valueWithRange:NSMakeRange(0, 15)];
    NSValue *range2 = [NSValue valueWithRange:NSMakeRange(10, 15)]; // Overlaps with range1
    
    NSArray *result = [NSArray validTokenPairRanges:@[range1, range2]];
    
    // Only the first (earlier) range should remain
    XCTAssertEqual(result.count, 1);
    XCTAssertEqualObjects(result[0], range1);
}

@end
