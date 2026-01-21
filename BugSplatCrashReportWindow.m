//
//  BugSplatCrashReportWindow.m
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#if TARGET_OS_OSX

#import "BugSplatCrashReportWindow.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kWindowWidth = 540.0;
static const CGFloat kPadding = 20.0;
static const CGFloat kFieldHeight = 24.0;
static const CGFloat kButtonWidth = 100.0;
static const CGFloat kButtonHeight = 32.0;
static const CGFloat kDetailsHeight = 200.0;

@interface BugSplatCrashReportWindow () <NSTextStorageDelegate>

@property (nonatomic, strong) NSStackView *mainStackView;
@property (nonatomic, strong) NSImageView *bannerImageView;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSView *userFieldsContainer;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *emailLabel;
@property (nonatomic, strong) NSTextField *emailField;
@property (nonatomic, strong) NSView *commentsContainer;
@property (nonatomic, strong) NSTextField *commentsLabel;
@property (nonatomic, strong) NSScrollView *commentsScrollView;
@property (nonatomic, strong) NSTextView *commentsTextView;
@property (nonatomic, strong) NSTextField *commentsPlaceholder;
@property (nonatomic, strong) NSView *detailsContainer;
@property (nonatomic, strong) NSScrollView *detailsScrollView;
@property (nonatomic, strong) NSTextView *detailsTextView;
@property (nonatomic, strong) NSView *buttonsContainer;
@property (nonatomic, strong) NSButton *showDetailsButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSTextField *footerLabel;

@property (nonatomic, copy) BugSplatCrashReportCompletion completion;
@property (nonatomic, strong) NSLayoutConstraint *detailsHeightConstraint;

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
        
        [self setupUI];
    }
    return self;
}

- (void)setupUI
{
    NSView *contentView = self.window.contentView;
    CGFloat contentWidth = kWindowWidth - (kPadding * 2);
    
    // Create main vertical stack view
    self.mainStackView = [[NSStackView alloc] init];
    self.mainStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.mainStackView.alignment = NSLayoutAttributeLeading;
    self.mainStackView.spacing = 8;
    self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mainStackView.edgeInsets = NSEdgeInsetsMake(kPadding, kPadding, kPadding, kPadding);
    [contentView addSubview:self.mainStackView];
    
    // Pin stack view to window edges
    [NSLayoutConstraint activateConstraints:@[
        [self.mainStackView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [self.mainStackView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.mainStackView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.mainStackView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];
    
    // === Banner Image ===
    self.bannerImageView = [[NSImageView alloc] init];
    self.bannerImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bannerImageView.imageScaling = NSImageScaleProportionallyDown;
    self.bannerImageView.imageAlignment = NSImageAlignCenter;
    [self.mainStackView addArrangedSubview:self.bannerImageView];
    [NSLayoutConstraint activateConstraints:@[
        [self.bannerImageView.widthAnchor constraintEqualToConstant:contentWidth],
        [self.bannerImageView.heightAnchor constraintEqualToConstant:110]
    ]];
    
    // Add extra spacing after banner
    [self.mainStackView setCustomSpacing:16 afterView:self.bannerImageView];
    
    // === Message Label ===
    self.messageLabel = [self createLabelWithText:@""];
    self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.messageLabel.font = [NSFont systemFontOfSize:13];
    self.messageLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.messageLabel.maximumNumberOfLines = 2;
    [self.mainStackView addArrangedSubview:self.messageLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.messageLabel.widthAnchor constraintEqualToConstant:contentWidth],
        [self.messageLabel.heightAnchor constraintEqualToConstant:40]
    ]];
    
    // === User Fields Container (Name/Email) ===
    [self setupUserFieldsContainer:contentWidth];
    [self.mainStackView addArrangedSubview:self.userFieldsContainer];
    
    // === Comments Container ===
    [self setupCommentsContainer:contentWidth];
    [self.mainStackView addArrangedSubview:self.commentsContainer];
    
    // === Details Container (collapsible) ===
    [self setupDetailsContainer:contentWidth];
    [self.mainStackView addArrangedSubview:self.detailsContainer];
    // Start collapsed - use height=0 and alpha=0 (not hidden)
    // This ensures the view always participates in layout, avoiding first-animation jank
    self.detailsHeightConstraint.constant = 0;
    self.detailsContainer.alphaValue = 0;
    
    // === Buttons Container ===
    [self setupButtonsContainer:contentWidth];
    [self.mainStackView addArrangedSubview:self.buttonsContainer];
    
    // === Footer Label ===
    self.footerLabel = [self createLabelWithText:@"Only the presented data will be sent with this report."];
    self.footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.footerLabel.font = [NSFont systemFontOfSize:11];
    self.footerLabel.textColor = [NSColor secondaryLabelColor];
    [self.mainStackView addArrangedSubview:self.footerLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.footerLabel.widthAnchor constraintEqualToConstant:contentWidth]
    ]];
}

- (void)setupUserFieldsContainer:(CGFloat)contentWidth
{
    self.userFieldsContainer = [[NSView alloc] init];
    self.userFieldsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    CGFloat fieldWidth = (contentWidth - 20) / 2;
    
    // Name label
    self.nameLabel = [self createLabelWithText:@"Name"];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font = [NSFont systemFontOfSize:13];
    [self.userFieldsContainer addSubview:self.nameLabel];
    
    // Name field
    self.nameField = [[NSTextField alloc] init];
    self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameField.placeholderString = @"";
    self.nameField.bezelStyle = NSTextFieldRoundedBezel;
    self.nameField.font = [NSFont systemFontOfSize:13];
    [self.userFieldsContainer addSubview:self.nameField];
    
    // Email label
    self.emailLabel = [self createLabelWithText:@"Email"];
    self.emailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emailLabel.font = [NSFont systemFontOfSize:13];
    [self.userFieldsContainer addSubview:self.emailLabel];
    
    // Email field
    self.emailField = [[NSTextField alloc] init];
    self.emailField.translatesAutoresizingMaskIntoConstraints = NO;
    self.emailField.placeholderString = @"";
    self.emailField.bezelStyle = NSTextFieldRoundedBezel;
    self.emailField.font = [NSFont systemFontOfSize:13];
    [self.userFieldsContainer addSubview:self.emailField];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.userFieldsContainer.widthAnchor constraintEqualToConstant:contentWidth],
        [self.userFieldsContainer.heightAnchor constraintEqualToConstant:kFieldHeight + 22],
        
        [self.nameLabel.topAnchor constraintEqualToAnchor:self.userFieldsContainer.topAnchor],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.userFieldsContainer.leadingAnchor],
        [self.nameLabel.widthAnchor constraintEqualToConstant:fieldWidth],
        
        [self.emailLabel.topAnchor constraintEqualToAnchor:self.userFieldsContainer.topAnchor],
        [self.emailLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor constant:20],
        [self.emailLabel.widthAnchor constraintEqualToConstant:fieldWidth],
        
        [self.nameField.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4],
        [self.nameField.leadingAnchor constraintEqualToAnchor:self.userFieldsContainer.leadingAnchor],
        [self.nameField.widthAnchor constraintEqualToConstant:fieldWidth],
        [self.nameField.heightAnchor constraintEqualToConstant:kFieldHeight],
        
        [self.emailField.topAnchor constraintEqualToAnchor:self.emailLabel.bottomAnchor constant:4],
        [self.emailField.leadingAnchor constraintEqualToAnchor:self.nameField.trailingAnchor constant:20],
        [self.emailField.widthAnchor constraintEqualToConstant:fieldWidth],
        [self.emailField.heightAnchor constraintEqualToConstant:kFieldHeight]
    ]];
}

- (void)setupCommentsContainer:(CGFloat)contentWidth
{
    self.commentsContainer = [[NSView alloc] init];
    self.commentsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Comments label
    self.commentsLabel = [self createLabelWithText:@"Comments"];
    self.commentsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.commentsLabel.font = [NSFont systemFontOfSize:13];
    [self.commentsContainer addSubview:self.commentsLabel];
    
    // Comments scroll view
    self.commentsScrollView = [[NSScrollView alloc] init];
    self.commentsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.commentsScrollView.hasVerticalScroller = YES;
    self.commentsScrollView.hasHorizontalScroller = NO;
    self.commentsScrollView.autohidesScrollers = YES;
    self.commentsScrollView.borderType = NSBezelBorder;
    [self.commentsContainer addSubview:self.commentsScrollView];
    
    // Comments text view
    self.commentsTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth - 20, 100)];
    self.commentsTextView.minSize = NSMakeSize(0, 100);
    self.commentsTextView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.commentsTextView.verticallyResizable = YES;
    self.commentsTextView.horizontallyResizable = NO;
    self.commentsTextView.autoresizingMask = NSViewWidthSizable;
    self.commentsTextView.textContainer.containerSize = NSMakeSize(contentWidth - 20, FLT_MAX);
    self.commentsTextView.textContainer.widthTracksTextView = YES;
    self.commentsTextView.textContainerInset = NSMakeSize(0, 4);
    self.commentsTextView.font = [NSFont systemFontOfSize:13];
    self.commentsTextView.textColor = [NSColor textColor];
    self.commentsTextView.textStorage.delegate = self;
    self.commentsScrollView.documentView = self.commentsTextView;
    
    // Placeholder label - use frame-based positioning (Auto Layout doesn't work well inside scroll views)
    self.commentsPlaceholder = [[NSTextField alloc] initWithFrame:NSMakeRect(5, 4, contentWidth - 10, 18)];
    self.commentsPlaceholder.stringValue = @"Please describe any steps needed to trigger the problem";
    self.commentsPlaceholder.bordered = NO;
    self.commentsPlaceholder.editable = NO;
    self.commentsPlaceholder.selectable = NO;
    self.commentsPlaceholder.drawsBackground = NO;
    self.commentsPlaceholder.textColor = [NSColor placeholderTextColor];
    self.commentsPlaceholder.font = [NSFont systemFontOfSize:13];
    [self.commentsScrollView addSubview:self.commentsPlaceholder];
    
    // Make clicks on placeholder activate the text view
    NSClickGestureRecognizer *placeholderClick = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(placeholderClicked:)];
    [self.commentsPlaceholder addGestureRecognizer:placeholderClick];
    
    CGFloat commentsHeight = 120;
    [NSLayoutConstraint activateConstraints:@[
        [self.commentsContainer.widthAnchor constraintEqualToConstant:contentWidth],
        [self.commentsContainer.heightAnchor constraintEqualToConstant:commentsHeight + 28],
        
        [self.commentsLabel.topAnchor constraintEqualToAnchor:self.commentsContainer.topAnchor],
        [self.commentsLabel.leadingAnchor constraintEqualToAnchor:self.commentsContainer.leadingAnchor],
        
        [self.commentsScrollView.topAnchor constraintEqualToAnchor:self.commentsLabel.bottomAnchor constant:8],
        [self.commentsScrollView.leadingAnchor constraintEqualToAnchor:self.commentsContainer.leadingAnchor],
        [self.commentsScrollView.trailingAnchor constraintEqualToAnchor:self.commentsContainer.trailingAnchor],
        [self.commentsScrollView.heightAnchor constraintEqualToConstant:commentsHeight]
    ]];
}

- (void)setupDetailsContainer:(CGFloat)contentWidth
{
    self.detailsContainer = [[NSView alloc] init];
    self.detailsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailsContainer.wantsLayer = YES;
    self.detailsContainer.layer.masksToBounds = YES; // Clip content when collapsed
    
    // Details scroll view
    self.detailsScrollView = [[NSScrollView alloc] init];
    self.detailsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailsScrollView.hasVerticalScroller = YES;
    self.detailsScrollView.hasHorizontalScroller = YES;
    self.detailsScrollView.autohidesScrollers = YES;
    self.detailsScrollView.borderType = NSBezelBorder;
    [self.detailsContainer addSubview:self.detailsScrollView];
    
    // Details text view
    self.detailsTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, kDetailsHeight)];
    self.detailsTextView.editable = NO;
    self.detailsTextView.font = [NSFont fontWithName:@"Menlo" size:11];
    if (!self.detailsTextView.font) {
        if (@available(macOS 10.15, *)) {
            self.detailsTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        } else {
            self.detailsTextView.font = [NSFont fontWithName:@"Courier" size:11] ?: [NSFont systemFontOfSize:11];
        }
    }
    self.detailsTextView.textContainer.widthTracksTextView = NO;
    self.detailsTextView.textContainer.containerSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.detailsScrollView.documentView = self.detailsTextView;
    
    self.detailsHeightConstraint = [self.detailsContainer.heightAnchor constraintEqualToConstant:kDetailsHeight];
    [NSLayoutConstraint activateConstraints:@[
        [self.detailsContainer.widthAnchor constraintEqualToConstant:contentWidth],
        self.detailsHeightConstraint,
        
        [self.detailsScrollView.topAnchor constraintEqualToAnchor:self.detailsContainer.topAnchor],
        [self.detailsScrollView.leadingAnchor constraintEqualToAnchor:self.detailsContainer.leadingAnchor],
        [self.detailsScrollView.trailingAnchor constraintEqualToAnchor:self.detailsContainer.trailingAnchor],
        [self.detailsScrollView.bottomAnchor constraintEqualToAnchor:self.detailsContainer.bottomAnchor]
    ]];
}

- (void)setupButtonsContainer:(CGFloat)contentWidth
{
    self.buttonsContainer = [[NSView alloc] init];
    self.buttonsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Show Details button
    self.showDetailsButton = [self createButtonWithTitle:@"Show Details" action:@selector(showDetailsClicked:)];
    self.showDetailsButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.showDetailsButton.bezelStyle = NSBezelStyleRounded;
    [self.buttonsContainer addSubview:self.showDetailsButton];
    
    // Cancel button
    self.cancelButton = [self createButtonWithTitle:@"Cancel" action:@selector(cancelClicked:)];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cancelButton.keyEquivalent = @"\033";
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    [self.buttonsContainer addSubview:self.cancelButton];
    
    // Send button
    self.sendButton = [self createButtonWithTitle:@"Send" action:@selector(sendClicked:)];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendButton.keyEquivalent = @"\r";
    self.sendButton.bezelStyle = NSBezelStyleRounded;
    [self.buttonsContainer addSubview:self.sendButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.buttonsContainer.widthAnchor constraintEqualToConstant:contentWidth],
        [self.buttonsContainer.heightAnchor constraintEqualToConstant:kButtonHeight],
        
        [self.showDetailsButton.leadingAnchor constraintEqualToAnchor:self.buttonsContainer.leadingAnchor],
        [self.showDetailsButton.centerYAnchor constraintEqualToAnchor:self.buttonsContainer.centerYAnchor],
        [self.showDetailsButton.widthAnchor constraintEqualToConstant:120],
        [self.showDetailsButton.heightAnchor constraintEqualToConstant:kButtonHeight],
        
        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.buttonsContainer.trailingAnchor],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.buttonsContainer.centerYAnchor],
        [self.sendButton.widthAnchor constraintEqualToConstant:kButtonWidth],
        [self.sendButton.heightAnchor constraintEqualToConstant:kButtonHeight],
        
        [self.cancelButton.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-10],
        [self.cancelButton.centerYAnchor constraintEqualToAnchor:self.buttonsContainer.centerYAnchor],
        [self.cancelButton.widthAnchor constraintEqualToConstant:kButtonWidth],
        [self.cancelButton.heightAnchor constraintEqualToConstant:kButtonHeight]
    ]];
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
    
    // Update banner image
    if (self.bannerImage) {
        self.bannerImageView.image = self.bannerImage;
    } else {
        self.bannerImageView.image = [self createDefaultBugSplatLogo];
    }
    
    // Update name/email fields visibility
    self.userFieldsContainer.hidden = !self.askUserDetails;
    
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
    
    // Update placeholder visibility
    [self updatePlaceholderVisibility];
}

- (NSImage *)createDefaultBugSplatLogo
{
    // Try to load the bundled logo image first
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSImage *bundledLogo = [bundle imageForResource:@"bugsplat-logo"];
    if (bundledLogo) {
        return bundledLogo;
    }
    
    // Fallback to programmatic logo if bundled image not found
    return [self createProgrammaticBugSplatLogo];
}

- (NSImage *)createProgrammaticBugSplatLogo
{
    CGFloat width = 440;
    CGFloat height = 110;
    
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image lockFocus];
    
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0, 0, width, height));
    
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    
    NSDictionary *mainAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:42],
        NSForegroundColorAttributeName: [NSColor colorWithRed:0.2 green:0.6 blue:0.86 alpha:1.0],
        NSParagraphStyleAttributeName: paragraphStyle
    };
    
    NSString *mainText = @"BugSplat";
    NSSize mainSize = [mainText sizeWithAttributes:mainAttrs];
    NSRect mainRect = NSMakeRect(0, (height - mainSize.height) / 2 + 10, width, mainSize.height);
    [mainText drawInRect:mainRect withAttributes:mainAttrs];
    
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

- (void)updatePlaceholderVisibility
{
    BOOL hasText = self.commentsTextView.string.length > 0;
    self.commentsPlaceholder.hidden = hasText;
}

- (void)showWithCompletion:(BugSplatCrashReportCompletion)completion
{
    self.completion = completion;
    [self updateUI];
    
    // Let Auto Layout calculate the size
    [self.window layoutIfNeeded];
    CGFloat height = self.mainStackView.fittingSize.height;
    NSRect frame = self.window.frame;
    frame.size.height = height;
    [self.window setFrame:frame display:NO];
    
    // Pre-warm Core Animation to avoid first-animation jank
    [self prewarmAnimationLayers];
    
    [self.window center];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    
    // Focus the comments field
    [self.window makeFirstResponder:self.commentsTextView];
}

- (void)showModalWithCompletion:(BugSplatCrashReportCompletion)completion
{
    self.completion = completion;
    [self updateUI];
    
    // Let Auto Layout calculate the size
    [self.window layoutIfNeeded];
    CGFloat height = self.mainStackView.fittingSize.height;
    NSRect frame = self.window.frame;
    frame.size.height = height;
    [self.window setFrame:frame display:NO];
    
    // Pre-warm Core Animation to avoid first-animation jank
    [self prewarmAnimationLayers];
    
    [self.window center];
    
    // Focus the comments field
    [self.window makeFirstResponder:self.commentsTextView];
    
    [NSApp runModalForWindow:self.window];
}

- (void)prewarmAnimationLayers
{
    // Force layer-backed rendering for smooth animations
    self.window.contentView.wantsLayer = YES;
    
    // Ensure the details container (which will animate) has its layer ready
    self.detailsContainer.wantsLayer = YES;
    self.detailsContainer.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    
    // Force complete layout pass
    [self.window.contentView layoutSubtreeIfNeeded];
}

#pragma mark - Actions

- (void)sendClicked:(id)sender
{
    NSString *name = self.nameField.stringValue ?: @"";
    NSString *email = self.emailField.stringValue ?: @"";
    NSString *comments = self.commentsTextView.string ?: @"";
    
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

- (void)placeholderClicked:(NSGestureRecognizer *)gesture
{
    [self.window makeFirstResponder:self.commentsTextView];
}

- (void)showDetailsClicked:(id)sender
{
    BOOL isCurrentlyCollapsed = (self.detailsHeightConstraint.constant == 0);
    
    self.showDetailsButton.title = isCurrentlyCollapsed ? @"Hide Details" : @"Show Details";
    
    CGFloat targetDetailsHeight = isCurrentlyCollapsed ? kDetailsHeight : 0;
    CGFloat heightDelta = targetDetailsHeight - self.detailsHeightConstraint.constant;
    
    // Animate everything together
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.25;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        
        // Animate the height constraint
        self.detailsHeightConstraint.animator.constant = targetDetailsHeight;
        
        // Animate the alpha
        self.detailsContainer.animator.alphaValue = isCurrentlyCollapsed ? 1.0 : 0.0;
        
        // Animate window frame - keep top edge fixed
        NSRect frame = self.window.frame;
        frame.origin.y -= heightDelta;
        frame.size.height += heightDelta;
        [self.window.animator setFrame:frame display:YES];
        
    } completionHandler:nil];
}

#pragma mark - NSTextStorageDelegate

- (void)textStorage:(NSTextStorage *)textStorage didProcessEditing:(NSTextStorageEditActions)editedMask range:(NSRange)editedRange changeInLength:(NSInteger)delta
{
    [self updatePlaceholderVisibility];
}

@end

#endif
