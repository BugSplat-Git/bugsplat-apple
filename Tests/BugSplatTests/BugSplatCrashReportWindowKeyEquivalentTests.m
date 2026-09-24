//
//  BugSplatCrashReportWindowKeyEquivalentTests.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import <TargetConditionals.h>

#if TARGET_OS_OSX

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "BugSplatCrashReportWindow.h"

#pragma mark - Recorder

/**
 * Sits on NSApp.delegate because a unit test process has no key window, so the window's
 * nil-target sendAction: ends up here and this can record what each key equivalent produced.
 */
@interface BugSplatEditingActionRecorder : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) NSMutableArray<NSString *> *performedActions;

@end

@implementation BugSplatEditingActionRecorder

- (instancetype)init
{
    self = [super init];
    if (self) {
        _performedActions = [NSMutableArray array];
    }
    return self;
}

- (void)recordAction:(SEL)action
{
    [self.performedActions addObject:NSStringFromSelector(action)];
}

- (void)selectAll:(id)sender { [self recordAction:_cmd]; }
- (void)copy:(id)sender { [self recordAction:_cmd]; }
- (void)paste:(id)sender { [self recordAction:_cmd]; }
- (void)cut:(id)sender { [self recordAction:_cmd]; }
- (void)undo:(id)sender { [self recordAction:_cmd]; }
- (void)redo:(id)sender { [self recordAction:_cmd]; }

@end

#pragma mark - Tests

@interface BugSplatCrashReportWindowKeyEquivalentTests : XCTestCase

@property (nonatomic, strong) BugSplatCrashReportWindow *controller;
@property (nonatomic, strong) BugSplatEditingActionRecorder *recorder;
@property (nonatomic, weak) id<NSApplicationDelegate> previousAppDelegate;

@end

@implementation BugSplatCrashReportWindowKeyEquivalentTests

- (void)setUp
{
    [super setUp];

    [NSApplication sharedApplication];

    self.previousAppDelegate = NSApp.delegate;
    self.recorder = [[BugSplatEditingActionRecorder alloc] init];
    NSApp.delegate = self.recorder;

    self.controller = [[BugSplatCrashReportWindow alloc] init];
    XCTAssertNotNil(self.controller.window);
}

- (void)tearDown
{
    NSApp.delegate = self.previousAppDelegate;
    self.recorder = nil;
    self.controller = nil;

    [super tearDown];
}

- (NSEvent *)keyEventWithCharacters:(NSString *)characters modifiers:(NSEventModifierFlags)modifiers
{
    return [NSEvent keyEventWithType:NSEventTypeKeyDown
                            location:NSZeroPoint
                       modifierFlags:modifiers
                           timestamp:0
                        windowNumber:self.controller.window.windowNumber
                             context:nil
                          characters:characters
         charactersIgnoringModifiers:characters
                           isARepeat:NO
                             keyCode:0];
}

- (BOOL)performKeyEquivalentForCharacters:(NSString *)characters modifiers:(NSEventModifierFlags)modifiers
{
    return [self.controller.window performKeyEquivalent:[self keyEventWithCharacters:characters modifiers:modifiers]];
}

- (void)testDialogWindowOverridesPerformKeyEquivalent
{
    // The dialog cannot rely on the host application having an Edit menu, so
    // its window has to translate the shortcuts itself.
    IMP dialogIMP = [self.controller.window.class instanceMethodForSelector:@selector(performKeyEquivalent:)];
    IMP baseIMP = [NSWindow instanceMethodForSelector:@selector(performKeyEquivalent:)];
    XCTAssertNotEqual(dialogIMP, baseIMP);
}

- (void)testCommandShortcutsSendTheStandardEditingActions
{
    NSDictionary<NSString *, NSString *> *expectedActions = @{
        @"a": @"selectAll:",
        @"c": @"copy:",
        @"v": @"paste:",
        @"x": @"cut:",
        @"z": @"undo:"
    };

    for (NSString *key in expectedActions) {
        [self.recorder.performedActions removeAllObjects];

        XCTAssertTrue([self performKeyEquivalentForCharacters:key modifiers:NSEventModifierFlagCommand],
                      @"Cmd+%@ should be handled by the dialog", key.uppercaseString);
        XCTAssertEqualObjects(self.recorder.performedActions, @[expectedActions[key]],
                              @"Cmd+%@ should send %@", key.uppercaseString, expectedActions[key]);
    }
}

- (void)testCommandShiftZSendsRedo
{
    XCTAssertTrue([self performKeyEquivalentForCharacters:@"Z"
                                                modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift]);
    XCTAssertEqualObjects(self.recorder.performedActions, @[@"redo:"]);
}

- (void)testUnrelatedKeyEquivalentsAreLeftToTheHostApplication
{
    NSArray<NSDictionary *> *unhandled = @[
        @{ @"characters": @"a", @"modifiers": @(0) },                                                              // no Command
        @{ @"characters": @"a", @"modifiers": @(NSEventModifierFlagCommand | NSEventModifierFlagControl) },        // Cmd+Ctrl+A
        @{ @"characters": @"a", @"modifiers": @(NSEventModifierFlagCommand | NSEventModifierFlagOption) },         // Cmd+Opt+A
        @{ @"characters": @"a", @"modifiers": @(NSEventModifierFlagCommand | NSEventModifierFlagShift) },          // Cmd+Shift+A
        @{ @"characters": @"q", @"modifiers": @(NSEventModifierFlagCommand) },                                     // Cmd+Q
        @{ @"characters": @"w", @"modifiers": @(NSEventModifierFlagCommand) },                                     // Cmd+W
        // Modifiers a Control/Option denylist would have let through.
        @{ @"characters": @"a", @"modifiers": @(NSEventModifierFlagCommand | NSEventModifierFlagFunction) },       // Cmd+Fn+A
        @{ @"characters": @"a", @"modifiers": @(NSEventModifierFlagCommand | NSEventModifierFlagHelp) },           // Cmd+Help+A
        @{ @"characters": @"a", @"modifiers": @(NSEventModifierFlagCommand | NSEventModifierFlagNumericPad) },     // Cmd+NumPad+A
        @{ @"characters": @"z", @"modifiers": @(NSEventModifierFlagCommand | NSEventModifierFlagShift
                                                | NSEventModifierFlagFunction) }                                   // Cmd+Shift+Fn+Z
    ];

    for (NSDictionary *event in unhandled) {
        NSString *characters = event[@"characters"];
        NSEventModifierFlags modifiers = [event[@"modifiers"] unsignedIntegerValue];

        XCTAssertFalse([self performKeyEquivalentForCharacters:characters modifiers:modifiers],
                       @"'%@' with modifiers %lu should be left for the host application",
                       characters, (unsigned long)modifiers);
    }

    XCTAssertEqual(self.recorder.performedActions.count, 0);
}

- (void)testCapsLockDoesNotSuppressTheShortcuts
{
    // Caps Lock is a stateful toggle rather than part of a chord, so someone typing with it on
    // must still get the editing shortcuts.
    XCTAssertTrue([self performKeyEquivalentForCharacters:@"a"
                                                modifiers:NSEventModifierFlagCommand | NSEventModifierFlagCapsLock]);
    XCTAssertEqualObjects(self.recorder.performedActions, @[@"selectAll:"]);

    [self.recorder.performedActions removeAllObjects];

    XCTAssertTrue([self performKeyEquivalentForCharacters:@"z"
                                                modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift
                                                          | NSEventModifierFlagCapsLock]);
    XCTAssertEqualObjects(self.recorder.performedActions, @[@"redo:"]);
}

- (void)testReturnStillTriggersSend
{
    XCTAssertTrue([self performKeyEquivalentForCharacters:@"\r" modifiers:0]);
    XCTAssertEqual(self.recorder.performedActions.count, 0);
}

- (void)testEscapeStillTriggersCancel
{
    XCTAssertTrue([self performKeyEquivalentForCharacters:@"\033" modifiers:0]);
    XCTAssertEqual(self.recorder.performedActions.count, 0);
}

@end

#endif
