//
//  BugSplatCrashReportWindow.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#if TARGET_OS_OSX

#import "BugSplatCrashReportWindow.h"

static const CGFloat kWindowWidth = 540.0;
static const CGFloat kPadding = 20.0;
static const CGFloat kFieldHeight = 24.0;
static const CGFloat kButtonWidth = 100.0;
static const CGFloat kButtonHeight = 32.0;

@interface BugSplatCrashReportWindow () <NSTextViewDelegate>

@property (nonatomic, strong) NSImageView *bannerImageView;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *emailLabel;
@property (nonatomic, strong) NSTextField *emailField;
@property (nonatomic, strong) NSButton *commentsDisclosure;
@property (nonatomic, strong) NSScrollView *commentsScrollView;
@property (nonatomic, strong) NSTextView *commentsTextView;
@property (nonatomic, strong) NSButton *showDetailsButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSTextField *footerLabel;
@property (nonatomic, strong) NSView *detailsContainer;
@property (nonatomic, strong) NSScrollView *detailsScrollView;
@property (nonatomic, strong) NSTextView *detailsTextView;

@property (nonatomic, copy) BugSplatCrashReportCompletion completion;
@property (nonatomic, assign) BOOL commentsExpanded;
@property (nonatomic, assign) BOOL detailsVisible;
@property (nonatomic, assign) BOOL showingPlaceholder;

@end

@implementation BugSplatCrashReportWindow

- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, 400)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    
    self = [super initWithWindow:window];
    if (self) {
        _askUserDetails = YES;
        _commentsExpanded = YES;
        _detailsVisible = NO;
        
        [self setupUI];
    }
    return self;
}

- (void)setupUI
{
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    
    CGFloat yOffset = 0;
    CGFloat contentWidth = kWindowWidth - (kPadding * 2);
    
    // Calculate layout from bottom to top
    
    // Footer label
    self.footerLabel = [self createLabelWithText:@"Only the presented data will be sent with this report."];
    self.footerLabel.font = [NSFont systemFontOfSize:11];
    self.footerLabel.textColor = [NSColor secondaryLabelColor];
    [contentView addSubview:self.footerLabel];
    yOffset = kPadding;
    self.footerLabel.frame = NSMakeRect(kPadding, yOffset, contentWidth, 16);
    yOffset += 20;
    
    // Buttons row
    self.sendButton = [self createButtonWithTitle:@"Send" action:@selector(sendClicked:)];
    self.sendButton.keyEquivalent = @"\r";
    self.sendButton.bezelStyle = NSBezelStyleRounded;
    [contentView addSubview:self.sendButton];
    
    self.cancelButton = [self createButtonWithTitle:@"Cancel" action:@selector(cancelClicked:)];
    self.cancelButton.keyEquivalent = @"\033";
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    [contentView addSubview:self.cancelButton];
    
    self.showDetailsButton = [self createButtonWithTitle:@"Show Details" action:@selector(showDetailsClicked:)];
    self.showDetailsButton.bezelStyle = NSBezelStyleRounded;
    [contentView addSubview:self.showDetailsButton];
    
    CGFloat buttonY = yOffset;
    self.sendButton.frame = NSMakeRect(kWindowWidth - kPadding - kButtonWidth, buttonY, kButtonWidth, kButtonHeight);
    self.cancelButton.frame = NSMakeRect(kWindowWidth - kPadding - kButtonWidth * 2 - 10, buttonY, kButtonWidth, kButtonHeight);
    self.showDetailsButton.frame = NSMakeRect(kPadding, buttonY, 120, kButtonHeight);
    yOffset += kButtonHeight + kPadding;
    
    // Comments section
    self.commentsDisclosure = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.commentsDisclosure.bezelStyle = NSBezelStyleDisclosure;
    self.commentsDisclosure.title = @"";
    self.commentsDisclosure.state = NSControlStateValueOn;
    self.commentsDisclosure.target = self;
    self.commentsDisclosure.action = @selector(commentsDisclosureClicked:);
    [contentView addSubview:self.commentsDisclosure];
    
    NSTextField *commentsLabel = [self createLabelWithText:@"Comments"];
    commentsLabel.font = [NSFont systemFontOfSize:13];
    [contentView addSubview:commentsLabel];
    
    self.commentsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.commentsScrollView.hasVerticalScroller = YES;
    self.commentsScrollView.hasHorizontalScroller = NO;
    self.commentsScrollView.autohidesScrollers = YES;
    self.commentsScrollView.borderType = NSBezelBorder;
    
    self.commentsTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth - 20, 100)];
    self.commentsTextView.minSize = NSMakeSize(0, 100);
    self.commentsTextView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.commentsTextView.verticallyResizable = YES;
    self.commentsTextView.horizontallyResizable = NO;
    self.commentsTextView.autoresizingMask = NSViewWidthSizable;
    self.commentsTextView.textContainer.containerSize = NSMakeSize(contentWidth - 20, FLT_MAX);
    self.commentsTextView.textContainer.widthTracksTextView = YES;
    self.commentsTextView.font = [NSFont systemFontOfSize:13];
    
    self.commentsTextView.delegate = self;
    
    self.commentsScrollView.documentView = self.commentsTextView;
    [contentView addSubview:self.commentsScrollView];
    
    CGFloat commentsHeight = 120;
    self.commentsScrollView.frame = NSMakeRect(kPadding, yOffset, contentWidth, commentsHeight);
    yOffset += commentsHeight + 8;
    
    self.commentsDisclosure.frame = NSMakeRect(kPadding - 4, yOffset, 20, 20);
    commentsLabel.frame = NSMakeRect(kPadding + 16, yOffset, 100, 20);
    yOffset += 28;
    
    // Email field
    self.emailLabel = [self createLabelWithText:@"Email"];
    self.emailLabel.font = [NSFont systemFontOfSize:13];
    [contentView addSubview:self.emailLabel];
    
    self.emailField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.emailField.placeholderString = @"";
    self.emailField.bezelStyle = NSTextFieldRoundedBezel;
    self.emailField.font = [NSFont systemFontOfSize:13];
    [contentView addSubview:self.emailField];
    
    // Name field
    self.nameLabel = [self createLabelWithText:@"Name"];
    self.nameLabel.font = [NSFont systemFontOfSize:13];
    [contentView addSubview:self.nameLabel];
    
    self.nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.nameField.placeholderString = @"";
    self.nameField.bezelStyle = NSTextFieldRoundedBezel;
    self.nameField.font = [NSFont systemFontOfSize:13];
    [contentView addSubview:self.nameField];
    
    CGFloat fieldWidth = (contentWidth - 20) / 2;
    self.nameLabel.frame = NSMakeRect(kPadding, yOffset + kFieldHeight + 4, fieldWidth, 18);
    self.emailLabel.frame = NSMakeRect(kPadding + fieldWidth + 20, yOffset + kFieldHeight + 4, fieldWidth, 18);
    self.nameField.frame = NSMakeRect(kPadding, yOffset, fieldWidth, kFieldHeight);
    self.emailField.frame = NSMakeRect(kPadding + fieldWidth + 20, yOffset, fieldWidth, kFieldHeight);
    yOffset += kFieldHeight + 26;
    
    // Message label
    self.messageLabel = [self createLabelWithText:@""];
    self.messageLabel.font = [NSFont systemFontOfSize:13];
    self.messageLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.messageLabel.maximumNumberOfLines = 2;
    [contentView addSubview:self.messageLabel];
    self.messageLabel.frame = NSMakeRect(kPadding, yOffset, contentWidth, 40);
    yOffset += 48;
    
    // Banner image
    self.bannerImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.bannerImageView.imageScaling = NSImageScaleProportionallyDown;
    self.bannerImageView.imageAlignment = NSImageAlignCenter;
    [contentView addSubview:self.bannerImageView];
    self.bannerImageView.frame = NSMakeRect(kPadding, yOffset, contentWidth, 110);
    yOffset += 110 + kPadding;
    
    // Set window height
    NSRect windowFrame = self.window.frame;
    windowFrame.size.height = yOffset;
    [self.window setFrame:windowFrame display:NO];
    
    // Details container (initially hidden)
    [self setupDetailsContainer];
}

- (void)setupDetailsContainer
{
    self.detailsContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    self.detailsContainer.hidden = YES;
    [self.window.contentView addSubview:self.detailsContainer];
    
    self.detailsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.detailsScrollView.hasVerticalScroller = YES;
    self.detailsScrollView.hasHorizontalScroller = YES;
    self.detailsScrollView.autohidesScrollers = YES;
    self.detailsScrollView.borderType = NSBezelBorder;
    
    self.detailsTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    self.detailsTextView.editable = NO;
    self.detailsTextView.font = [NSFont fontWithName:@"Menlo" size:11];
    if (!self.detailsTextView.font) {
        // Fallback for when Menlo isn't available
        if (@available(macOS 10.15, *)) {
            self.detailsTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        } else {
            self.detailsTextView.font = [NSFont fontWithName:@"Courier" size:11] ?: [NSFont systemFontOfSize:11];
        }
    }
    self.detailsTextView.textContainer.widthTracksTextView = NO;
    self.detailsTextView.textContainer.containerSize = NSMakeSize(FLT_MAX, FLT_MAX);
    
    self.detailsScrollView.documentView = self.detailsTextView;
    [self.detailsContainer addSubview:self.detailsScrollView];
}

- (NSTextField *)createLabelWithText:(NSString *)text
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    label.stringValue = text;
    label.bordered = NO;
    label.editable = NO;
    label.selectable = NO;
    label.drawsBackground = NO;
    label.textColor = [NSColor labelColor];
    return label;
}

- (NSButton *)createButtonWithTitle:(NSString *)title action:(SEL)action
{
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.title = title;
    button.target = self;
    button.action = action;
    return button;
}

- (void)updateUI
{
    // Update window title
    self.window.title = [NSString stringWithFormat:@"Problem Report for %@", self.applicationName ?: @"Application"];
    
    // Update message
    self.messageLabel.stringValue = [NSString stringWithFormat:@"%@ unexpectedly quit. Would you like to send a report so we can fix the problem?", self.applicationName ?: @"The application"];
    
    // Update banner image - use custom image or default BugSplat logo
    if (self.bannerImage) {
        self.bannerImageView.image = self.bannerImage;
    } else {
        self.bannerImageView.image = [self createDefaultBugSplatLogo];
    }
    
    // Update name/email fields visibility
    self.nameLabel.hidden = !self.askUserDetails;
    self.nameField.hidden = !self.askUserDetails;
    self.emailLabel.hidden = !self.askUserDetails;
    self.emailField.hidden = !self.askUserDetails;
    
    // Pre-fill fields
    if (self.prefillUserName) {
        self.nameField.stringValue = self.prefillUserName;
    }
    if (self.prefillUserEmail) {
        self.emailField.stringValue = self.prefillUserEmail;
    }
    
    // Update details text
    if (self.crashReportText) {
        self.detailsTextView.string = self.crashReportText;
    }
    
    // Update placeholder
    [self updateCommentsPlaceholder];
}

- (NSImage *)createDefaultBugSplatLogo
{
    CGFloat width = 440;
    CGFloat height = 110;
    
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image lockFocus];
    
    // Draw background (transparent)
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0, 0, width, height));
    
    // Draw BugSplat text
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    
    // Main "BugSplat" text
    NSDictionary *mainAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:42],
        NSForegroundColorAttributeName: [NSColor colorWithRed:0.2 green:0.6 blue:0.86 alpha:1.0], // BugSplat blue
        NSParagraphStyleAttributeName: paragraphStyle
    };
    
    NSString *mainText = @"BugSplat";
    NSSize mainSize = [mainText sizeWithAttributes:mainAttrs];
    NSRect mainRect = NSMakeRect(0, (height - mainSize.height) / 2 + 10, width, mainSize.height);
    [mainText drawInRect:mainRect withAttributes:mainAttrs];
    
    // Tagline
    NSDictionary *taglineAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
        NSParagraphStyleAttributeName: paragraphStyle
    };
    
    NSString *tagline = @"Crash Reporting";
    NSSize taglineSize = [tagline sizeWithAttributes:taglineAttrs];
    NSRect taglineRect = NSMakeRect(0, (height - mainSize.height) / 2 - taglineSize.height + 5, width, taglineSize.height);
    [tagline drawInRect:taglineRect withAttributes:taglineAttrs];
    
    [image unlockFocus];
    
    return image;
}

- (void)updateCommentsPlaceholder
{
    if (self.commentsTextView.string.length == 0 || self.showingPlaceholder) {
        self.showingPlaceholder = YES;
        self.commentsTextView.string = @"Please describe any steps needed to trigger the problem";
        self.commentsTextView.textColor = [NSColor placeholderTextColor];
    }
}

- (void)clearPlaceholderIfNeeded
{
    if (self.showingPlaceholder) {
        self.showingPlaceholder = NO;
        self.commentsTextView.string = @"";
        self.commentsTextView.textColor = [NSColor textColor];
    }
}

- (void)showWithCompletion:(BugSplatCrashReportCompletion)completion
{
    self.completion = completion;
    [self updateUI];
    [self relayoutWindow];
    [self.window center];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showModalWithCompletion:(BugSplatCrashReportCompletion)completion
{
    self.completion = completion;
    [self updateUI];
    [self relayoutWindow];
    [self.window center];
    [NSApp runModalForWindow:self.window];
}

#pragma mark - Actions

- (void)sendClicked:(id)sender
{
    NSString *name = self.nameField.stringValue;
    NSString *email = self.emailField.stringValue;
    NSString *comments = self.showingPlaceholder ? @"" : self.commentsTextView.string;
    
    [self.window close];
    [NSApp stopModal];
    
    if (self.completion) {
        self.completion(BugSplatUserActionSend, name, email, comments);
    }
}

- (void)cancelClicked:(id)sender
{
    [self.window close];
    [NSApp stopModal];
    
    if (self.completion) {
        self.completion(BugSplatUserActionCancel, nil, nil, nil);
    }
}

- (void)commentsDisclosureClicked:(id)sender
{
    self.commentsExpanded = !self.commentsExpanded;
    self.commentsDisclosure.state = self.commentsExpanded ? NSControlStateValueOn : NSControlStateValueOff;
    self.commentsScrollView.hidden = !self.commentsExpanded;
    
    [self relayoutWindow];
}

- (void)showDetailsClicked:(id)sender
{
    self.detailsVisible = !self.detailsVisible;
    self.showDetailsButton.title = self.detailsVisible ? @"Hide Details" : @"Show Details";
    self.detailsContainer.hidden = !self.detailsVisible;
    
    [self relayoutWindow];
}

- (void)relayoutWindow
{
    CGFloat contentWidth = kWindowWidth - (kPadding * 2);
    CGFloat yOffset = kPadding;
    
    // Layout from bottom to top:
    // Footer -> Buttons -> Details (if visible) -> Comments -> Name/Email -> Message -> Banner
    
    // Footer at bottom
    self.footerLabel.frame = NSMakeRect(kPadding, yOffset, contentWidth, 16);
    yOffset += 20;
    
    // Buttons row (above footer)
    self.sendButton.frame = NSMakeRect(kWindowWidth - kPadding - kButtonWidth, yOffset, kButtonWidth, kButtonHeight);
    self.cancelButton.frame = NSMakeRect(kWindowWidth - kPadding - kButtonWidth * 2 - 10, yOffset, kButtonWidth, kButtonHeight);
    self.showDetailsButton.frame = NSMakeRect(kPadding, yOffset, 120, kButtonHeight);
    yOffset += kButtonHeight + kPadding;
    
    // Details section (if visible) - between buttons and comments
    if (self.detailsVisible) {
        CGFloat detailsHeight = 200;
        self.detailsContainer.frame = NSMakeRect(0, yOffset, kWindowWidth, detailsHeight);
        self.detailsScrollView.frame = NSMakeRect(kPadding, 5, contentWidth, detailsHeight - 10);
        yOffset += detailsHeight + kPadding;
    }
    
    // Comments section
    if (self.commentsExpanded) {
        CGFloat commentsHeight = 120;
        self.commentsScrollView.frame = NSMakeRect(kPadding, yOffset, contentWidth, commentsHeight);
        yOffset += commentsHeight + 8;
    }
    
    // Comments label and disclosure
    NSView *commentsLabel = nil;
    for (NSView *subview in self.window.contentView.subviews) {
        if ([subview isKindOfClass:[NSTextField class]]) {
            NSTextField *tf = (NSTextField *)subview;
            if ([tf.stringValue isEqualToString:@"Comments"]) {
                commentsLabel = tf;
                break;
            }
        }
    }
    self.commentsDisclosure.frame = NSMakeRect(kPadding - 4, yOffset, 20, 20);
    if (commentsLabel) {
        commentsLabel.frame = NSMakeRect(kPadding + 16, yOffset, 100, 20);
    }
    yOffset += 28;
    
    // Name/Email fields
    CGFloat fieldWidth = (contentWidth - 20) / 2;
    self.nameLabel.frame = NSMakeRect(kPadding, yOffset + kFieldHeight + 4, fieldWidth, 18);
    self.emailLabel.frame = NSMakeRect(kPadding + fieldWidth + 20, yOffset + kFieldHeight + 4, fieldWidth, 18);
    self.nameField.frame = NSMakeRect(kPadding, yOffset, fieldWidth, kFieldHeight);
    self.emailField.frame = NSMakeRect(kPadding + fieldWidth + 20, yOffset, fieldWidth, kFieldHeight);
    yOffset += kFieldHeight + 26;
    
    // Message label
    self.messageLabel.frame = NSMakeRect(kPadding, yOffset, contentWidth, 40);
    yOffset += 48;
    
    // Banner image (always visible - use default if no custom image)
    self.bannerImageView.frame = NSMakeRect(kPadding, yOffset, contentWidth, 110);
    yOffset += 110 + kPadding;
    
    // Resize window
    NSRect frame = self.window.frame;
    CGFloat heightDiff = yOffset - frame.size.height;
    frame.size.height = yOffset;
    frame.origin.y -= heightDiff;
    
    [self.window setFrame:frame display:YES animate:YES];
}

#pragma mark - NSTextViewDelegate

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString
{
    if (textView == self.commentsTextView && self.showingPlaceholder) {
        // User is typing - clear placeholder first
        dispatch_async(dispatch_get_main_queue(), ^{
            [self clearPlaceholderIfNeeded];
            // Insert the typed character
            if (replacementString.length > 0) {
                [self.commentsTextView insertText:replacementString replacementRange:NSMakeRange(0, 0)];
            }
        });
        return NO; // We'll handle the text insertion ourselves
    }
    return YES;
}

- (void)textDidEndEditing:(NSNotification *)notification
{
    if (self.commentsTextView.string.length == 0) {
        [self updateCommentsPlaceholder];
    }
}

@end

#endif
