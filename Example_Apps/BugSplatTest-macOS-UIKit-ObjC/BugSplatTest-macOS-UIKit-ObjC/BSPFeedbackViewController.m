//
//  BSPFeedbackViewController.m
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BSPFeedbackViewController.h"
#import "BSPDemoTheme.h"
#import "BSPActivityLog.h"
#import <BugSplat/BugSplat.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static CGFloat const kBSPFeedbackWidth = 480.0;

#pragma mark - Sample log helper

/// Locates the `sample_log.txt` file the app writes at launch (see AppDelegate)
/// so it can be attached to feedback when the user opts in.
@interface BSPSampleLog : NSObject
+ (nullable BugSplatAttachment *)attachment;
@end

@implementation BSPSampleLog

+ (BugSplatAttachment *)attachment {
    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                          inDomains:NSUserDomainMask] firstObject];
    NSURL *url = [docs URLByAppendingPathComponent:@"sample_log.txt"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    if (!data) return nil;
    return [[BugSplatAttachment alloc] initWithFilename:@"sample_log.txt"
                                         attachmentData:data
                                            contentType:@"text/plain"];
}

@end

#pragma mark - Feedback view controller

@interface BSPFeedbackViewController () <NSTextFieldDelegate>

@property (nonatomic, strong) NSView *formContainer;
@property (nonatomic, strong) NSView *thanksContainer;

@property (nonatomic, strong) NSSegmentedControl *segmented;
@property (nonatomic, strong) NSTextField *titleField;
@property (nonatomic, strong) NSTextView *descriptionView;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *emailField;
@property (nonatomic, strong) NSButton *includeLogsSwitch;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSProgressIndicator *sendSpinner;

@property (nonatomic, strong) NSTextField *attachmentTypeChip;
@property (nonatomic, strong) NSTextField *attachmentNameLabel;
@property (nonatomic, strong) NSTextField *attachmentDetailLabel;
@property (nonatomic, strong) NSButton *attachmentActionButton;

@property (nonatomic, copy, nullable) NSString *pickedFileName;
@property (nonatomic, strong, nullable) NSData *pickedFileData;
@property (nonatomic, assign) BOOL submitting;

/// The submitted feedback result, retained so the thank-you actions can use it.
@property (nonatomic, strong, nullable) BugSplatFeedbackResult *thanksResult;

@end

@implementation BSPFeedbackViewController

- (NSString *)database {
    return [BugSplat shared].bugSplatDatabase ?: @"—";
}

- (NSString *)selectedCategory {
    NSArray<NSString *> *categories = @[ @"Bug", @"Feature", @"Other" ];
    NSInteger index = self.segmented.selectedSegment;
    if (index < 0 || index >= (NSInteger)categories.count) return @"Bug";
    return categories[index];
}

#pragma mark - Lifecycle

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kBSPFeedbackWidth, 640)];
    root.wantsLayer = YES;
    root.layer.backgroundColor = [BSPDemoTheme cardBg].CGColor;
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.preferredContentSize = NSMakeSize(kBSPFeedbackWidth, 640);
    [self buildForm];
    [self renderAttachmentRow];
    [self updateSendEnabled];
}

- (void)viewDidDisappear {
    [super viewDidDisappear];
    if (self.onDismiss) self.onDismiss();
}

#pragma mark - Form layout

- (void)buildForm {
    self.formContainer = [NSView new];
    self.formContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.formContainer];
    [self pinView:self.formContainer toEdgesOf:self.view];

    NSView *header = [self makeHeaderWithTitle:@"Send feedback"];
    NSView *headerDivider = [self makeDivider];
    NSView *footer = [self makeFormFooter];

    NSStackView *fields = [NSStackView new];
    fields.translatesAutoresizingMaskIntoConstraints = NO;
    fields.orientation = NSUserInterfaceLayoutOrientationVertical;
    fields.alignment = NSLayoutAttributeLeading;
    fields.spacing = 16;

    self.segmented = [NSSegmentedControl segmentedControlWithLabels:@[ @"Bug", @"Feature", @"Other" ]
                                                       trackingMode:NSSegmentSwitchTrackingSelectOne
                                                             target:nil
                                                             action:nil];
    self.segmented.selectedSegment = 0;
    [self addArrangedField:self.segmented to:fields];

    self.titleField = [self makeTextField];
    [fields addArrangedSubview:[self makeFieldWithLabel:@"Title" required:YES input:[self boxedInput:self.titleField height:36]]];

    NSScrollView *descScroll = [self makeDescriptionScroll];
    [fields addArrangedSubview:[self makeFieldWithLabel:@"Description" required:NO input:descScroll]];

    self.nameField = [self makeTextField];
    [fields addArrangedSubview:[self makeFieldWithLabel:@"Name" required:NO input:[self boxedInput:self.nameField height:36]]];

    self.emailField = [self makeTextField];
    [fields addArrangedSubview:[self makeFieldWithLabel:@"Email" required:NO input:[self boxedInput:self.emailField height:36]]];

    [fields addArrangedSubview:[self makeFieldWithLabel:@"Attachment" required:NO input:[self makeAttachmentRow]]];

    [self addArrangedField:[self makeIncludeLogsRow] to:fields];

    self.errorLabel = [self plainLabel:@"" size:12 color:[BSPDemoTheme asterisk]];
    self.errorLabel.hidden = YES;
    [self addArrangedField:self.errorLabel to:fields];

    NSStackView *layout = [NSStackView stackViewWithViews:@[ header, headerDivider, fields, footer ]];
    layout.translatesAutoresizingMaskIntoConstraints = NO;
    layout.orientation = NSUserInterfaceLayoutOrientationVertical;
    layout.alignment = NSLayoutAttributeLeading;
    layout.spacing = 0;
    [layout setCustomSpacing:18 afterView:headerDivider];
    [layout setCustomSpacing:18 afterView:fields];
    [self.formContainer addSubview:layout];

    [NSLayoutConstraint activateConstraints:@[
        [layout.topAnchor constraintEqualToAnchor:self.formContainer.topAnchor],
        [layout.leadingAnchor constraintEqualToAnchor:self.formContainer.leadingAnchor],
        [layout.trailingAnchor constraintEqualToAnchor:self.formContainer.trailingAnchor],
        [layout.bottomAnchor constraintEqualToAnchor:self.formContainer.bottomAnchor],

        [header.leadingAnchor constraintEqualToAnchor:layout.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:layout.trailingAnchor],
        [headerDivider.leadingAnchor constraintEqualToAnchor:layout.leadingAnchor],
        [headerDivider.trailingAnchor constraintEqualToAnchor:layout.trailingAnchor],
        [footer.leadingAnchor constraintEqualToAnchor:layout.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:layout.trailingAnchor],
        [fields.leadingAnchor constraintEqualToAnchor:layout.leadingAnchor constant:20],
        [fields.trailingAnchor constraintEqualToAnchor:layout.trailingAnchor constant:-20],
        [fields.topAnchor constraintEqualToAnchor:headerDivider.bottomAnchor constant:18],
    ]];
}

/// Add a field row that should stretch to the full content width.
- (void)addArrangedField:(NSView *)field to:(NSStackView *)stack {
    [stack addArrangedSubview:field];
    [field.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [field.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
}

- (NSView *)makeHeaderWithTitle:(NSString *)title {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
    label.textColor = [BSPDemoTheme textPrimary];
    label.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *close = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark"
                                                         accessibilityDescription:@"Close"]
                                         target:self
                                         action:@selector(closeTapped)];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    close.bordered = NO;
    close.contentTintColor = [BSPDemoTheme textSecondary];

    NSView *bar = [NSView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:label];
    [bar addSubview:close];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:20],
        [label.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [label.topAnchor constraintEqualToAnchor:bar.topAnchor constant:16],
        [label.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-16],
        [close.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-20],
        [close.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
    ]];
    return bar;
}

- (NSView *)makeFormFooter {
    NSTextField *hint = [NSTextField labelWithString:@"Press any 6 keys at once to send feedback."];
    hint.font = [NSFont systemFontOfSize:12];
    hint.textColor = [BSPDemoTheme textTertiary];
    hint.alignment = NSTextAlignmentCenter;

    self.sendButton = [NSButton buttonWithTitle:@"Send feedback  →" target:self action:@selector(submitTapped)];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendButton.bezelStyle = NSBezelStyleRounded;
    self.sendButton.keyEquivalent = @"\r";
    self.sendButton.controlSize = NSControlSizeLarge;
    self.sendButton.bezelColor = [BSPDemoTheme feedbackAccent];
    [self.sendButton.heightAnchor constraintEqualToConstant:36].active = YES;

    self.sendSpinner = [NSProgressIndicator new];
    self.sendSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendSpinner.style = NSProgressIndicatorStyleSpinning;
    self.sendSpinner.controlSize = NSControlSizeSmall;
    self.sendSpinner.displayedWhenStopped = NO;
    [self.sendButton addSubview:self.sendSpinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.sendSpinner.centerXAnchor constraintEqualToAnchor:self.sendButton.centerXAnchor],
        [self.sendSpinner.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
    ]];

    NSStackView *stack = [NSStackView stackViewWithViews:@[ hint, self.sendButton ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(14, 20, 20, 20);

    return [self footerContainerWithContent:stack stretchView:self.sendButton];
}

- (NSView *)footerContainerWithContent:(NSStackView *)content stretchView:(nullable NSView *)stretch {
    NSView *container = [NSView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.wantsLayer = YES;
    container.layer.backgroundColor = [BSPDemoTheme footerBg].CGColor;
    NSView *divider = [self makeDivider];
    [container addSubview:divider];
    [container addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [divider.topAnchor constraintEqualToAnchor:container.topAnchor],
        [divider.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:container.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    if (stretch) {
        [stretch.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20].active = YES;
        [stretch.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20].active = YES;
    }
    return container;
}

- (NSScrollView *)makeDescriptionScroll {
    NSScrollView *scroll = [NSScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    scroll.wantsLayer = YES;
    scroll.layer.cornerRadius = 8;
    scroll.layer.borderWidth = 1;
    scroll.layer.borderColor = [BSPDemoTheme cardStroke].CGColor;
    [scroll.heightAnchor constraintEqualToConstant:84].active = YES;

    self.descriptionView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.descriptionView.font = [NSFont systemFontOfSize:13];
    self.descriptionView.textColor = [BSPDemoTheme textPrimary];
    self.descriptionView.drawsBackground = YES;
    self.descriptionView.backgroundColor = [BSPDemoTheme cardBg];
    self.descriptionView.textContainerInset = NSMakeSize(6, 7);
    self.descriptionView.richText = NO;
    self.descriptionView.automaticQuoteSubstitutionEnabled = NO;
    scroll.documentView = self.descriptionView;
    return scroll;
}

- (NSView *)makeAttachmentRow {
    NSView *row = [NSView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.wantsLayer = YES;
    row.layer.backgroundColor = [BSPDemoTheme cardBg].CGColor;
    row.layer.cornerRadius = 8;
    row.layer.borderWidth = 1;
    row.layer.borderColor = [BSPDemoTheme cardStroke].CGColor;

    self.attachmentTypeChip = [NSTextField labelWithString:@""];
    self.attachmentTypeChip.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentTypeChip.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    self.attachmentTypeChip.textColor = [BSPDemoTheme textSecondary];
    self.attachmentTypeChip.alignment = NSTextAlignmentCenter;
    self.attachmentTypeChip.wantsLayer = YES;
    self.attachmentTypeChip.layer.backgroundColor = [BSPDemoTheme badgeBg].CGColor;
    self.attachmentTypeChip.layer.cornerRadius = 6;

    self.attachmentNameLabel = [NSTextField labelWithString:@""];
    self.attachmentNameLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.attachmentNameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    self.attachmentDetailLabel = [NSTextField labelWithString:@""];
    self.attachmentDetailLabel.font = [NSFont systemFontOfSize:11];
    self.attachmentDetailLabel.textColor = [BSPDemoTheme textTertiary];

    NSStackView *textStack = [NSStackView stackViewWithViews:@[ self.attachmentNameLabel, self.attachmentDetailLabel ]];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    textStack.alignment = NSLayoutAttributeLeading;
    textStack.spacing = 2;

    self.attachmentActionButton = [NSButton buttonWithTitle:@"Add" target:self action:@selector(pickFileTapped)];
    self.attachmentActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentActionButton.bordered = NO;
    self.attachmentActionButton.contentTintColor = [BSPDemoTheme link];
    self.attachmentActionButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];

    [row addSubview:self.attachmentTypeChip];
    [row addSubview:textStack];
    [row addSubview:self.attachmentActionButton];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:60],
        [self.attachmentTypeChip.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [self.attachmentTypeChip.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [self.attachmentTypeChip.widthAnchor constraintEqualToConstant:40],
        [self.attachmentTypeChip.heightAnchor constraintEqualToConstant:40],

        [textStack.leadingAnchor constraintEqualToAnchor:self.attachmentTypeChip.trailingAnchor constant:12],
        [textStack.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [self.attachmentActionButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:textStack.trailingAnchor constant:8],
        [self.attachmentActionButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [self.attachmentActionButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

- (void)renderAttachmentRow {
    if (self.pickedFileName.length > 0 && self.pickedFileData) {
        NSString *ext = self.pickedFileName.pathExtension.uppercaseString;
        self.attachmentTypeChip.stringValue = ext.length > 0 ? ext : @"FILE";
        self.attachmentTypeChip.hidden = NO;
        self.attachmentNameLabel.stringValue = self.pickedFileName;
        self.attachmentNameLabel.textColor = [BSPDemoTheme textPrimary];
        self.attachmentDetailLabel.stringValue =
            [NSByteCountFormatter stringFromByteCount:(long long)self.pickedFileData.length
                                           countStyle:NSByteCountFormatterCountStyleFile];
        self.attachmentDetailLabel.hidden = NO;
        self.attachmentActionButton.title = @"Replace";
    } else {
        self.attachmentTypeChip.hidden = YES;
        self.attachmentNameLabel.stringValue = @"No file selected";
        self.attachmentNameLabel.textColor = [BSPDemoTheme textTertiary];
        self.attachmentDetailLabel.hidden = YES;
        self.attachmentActionButton.title = @"Add";
    }
}

- (NSView *)makeIncludeLogsRow {
    NSTextField *title = [NSTextField labelWithString:@"Include logs"];
    title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    title.textColor = [BSPDemoTheme textPrimary];

    NSTextField *subtitle = [NSTextField labelWithString:@"Attach the app's sample_log.txt"];
    subtitle.font = [NSFont systemFontOfSize:11];
    subtitle.textColor = [BSPDemoTheme textTertiary];

    NSStackView *textStack = [NSStackView stackViewWithViews:@[ title, subtitle ]];
    textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    textStack.alignment = NSLayoutAttributeLeading;
    textStack.spacing = 2;

    self.includeLogsSwitch = [NSButton new];
    self.includeLogsSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.includeLogsSwitch setButtonType:NSButtonTypeSwitch];
    self.includeLogsSwitch.title = @"";
    self.includeLogsSwitch.state = NSControlStateValueOn;

    NSView *spacer = [NSView new];
    NSStackView *row = [NSStackView stackViewWithViews:@[ textStack, spacer, self.includeLogsSwitch ]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12;
    [row setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return row;
}

#pragma mark - Field helpers

- (NSTextField *)makeTextField {
    NSTextField *field = [NSTextField new];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = [NSFont systemFontOfSize:13];
    field.textColor = [BSPDemoTheme textPrimary];
    field.bordered = NO;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.delegate = self;
    return field;
}

/// Wraps an input control in a rounded, outlined box.
- (NSView *)boxedInput:(NSView *)input height:(CGFloat)height {
    NSView *box = [NSView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.wantsLayer = YES;
    box.layer.backgroundColor = [BSPDemoTheme cardBg].CGColor;
    box.layer.cornerRadius = 8;
    box.layer.borderWidth = 1;
    box.layer.borderColor = [BSPDemoTheme cardStroke].CGColor;
    [box addSubview:input];
    [NSLayoutConstraint activateConstraints:@[
        [box.heightAnchor constraintEqualToConstant:height],
        [input.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:10],
        [input.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-10],
        [input.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
    ]];
    return box;
}

/// A labeled field: a header row (label + red asterisk or "optional") above the input.
- (NSView *)makeFieldWithLabel:(NSString *)label required:(BOOL)required input:(NSView *)input {
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc]
        initWithString:label
            attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                          NSForegroundColorAttributeName: [BSPDemoTheme textPrimary] }];
    if (required) {
        [attributed appendAttributedString:[[NSAttributedString alloc]
            initWithString:@" *"
                attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                              NSForegroundColorAttributeName: [BSPDemoTheme asterisk] }]];
    }
    NSTextField *labelView = [NSTextField labelWithAttributedString:attributed];

    NSView *headerRow;
    if (required) {
        headerRow = labelView;
    } else {
        NSTextField *optional = [NSTextField labelWithString:@"optional"];
        optional.font = [NSFont systemFontOfSize:12];
        optional.textColor = [BSPDemoTheme textTertiary];
        NSView *spacer = [NSView new];
        NSStackView *row = [NSStackView stackViewWithViews:@[ labelView, spacer, optional ]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.spacing = 6;
        headerRow = row;
    }

    NSStackView *stack = [NSStackView stackViewWithViews:@[ headerRow, input ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    [headerRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [headerRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
    [input.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [input.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
    return stack;
}

- (NSTextField *)plainLabel:(NSString *)text size:(CGFloat)size color:(NSColor *)color {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:size];
    label.textColor = color;
    label.selectable = NO;
    return label;
}

- (NSView *)makeDivider {
    NSView *divider = [NSView new];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.wantsLayer = YES;
    divider.layer.backgroundColor = [BSPDemoTheme cardStroke].CGColor;
    [divider.heightAnchor constraintEqualToConstant:1].active = YES;
    return divider;
}

- (void)pinView:(NSView *)view toEdgesOf:(NSView *)container {
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:container.topAnchor],
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
}

#pragma mark - Form actions

/// NSTextFieldDelegate — re-evaluate the Send button as the title is typed.
- (void)controlTextDidChange:(NSNotification *)notification {
    [self updateSendEnabled];
}

- (void)closeTapped {
    [self dismissViewController:self];
}

- (void)updateSendEnabled {
    NSString *trimmed = [self.titleField.stringValue
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.sendButton.enabled = trimmed.length > 0 && !self.submitting;
}

- (void)pickFileTapped {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || result != NSModalResponseOK) return;
        NSURL *url = panel.URL;
        NSError *error = nil;
        NSData *data = url ? [NSData dataWithContentsOfURL:url options:0 error:&error] : nil;
        if (data) {
            strongSelf.pickedFileData = data;
            strongSelf.pickedFileName = url.lastPathComponent;
            [strongSelf renderAttachmentRow];
        } else {
            strongSelf.errorLabel.stringValue =
                [NSString stringWithFormat:@"Couldn't read the selected file: %@", error.localizedDescription];
            strongSelf.errorLabel.hidden = NO;
        }
    }];
}

- (void)setSubmitting:(BOOL)submitting {
    _submitting = submitting;
    if (submitting) {
        self.sendButton.title = @"";
        [self.sendSpinner startAnimation:nil];
    } else {
        self.sendButton.title = @"Send feedback  →";
        [self.sendSpinner stopAnimation:nil];
    }
    self.segmented.enabled = !submitting;
    self.titleField.enabled = !submitting;
    self.descriptionView.editable = !submitting;
    self.nameField.enabled = !submitting;
    self.emailField.enabled = !submitting;
    self.includeLogsSwitch.enabled = !submitting;
    self.attachmentActionButton.enabled = !submitting;
    [self updateSendEnabled];
}

- (void)submitTapped {
    NSString *trimmedTitle = [self.titleField.stringValue
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedTitle.length == 0) return;

    self.errorLabel.hidden = YES;
    [self setSubmitting:YES];

    NSMutableArray<BugSplatAttachment *> *attachments = [NSMutableArray array];
    if (self.pickedFileName.length > 0 && self.pickedFileData) {
        UTType *type = [UTType typeWithFilenameExtension:self.pickedFileName.pathExtension];
        NSString *mime = type.preferredMIMEType ?: @"application/octet-stream";
        [attachments addObject:[[BugSplatAttachment alloc] initWithFilename:self.pickedFileName
                                                             attachmentData:self.pickedFileData
                                                                contentType:mime]];
    }
    if (self.includeLogsSwitch.state == NSControlStateValueOn) {
        BugSplatAttachment *log = [BSPSampleLog attachment];
        if (log) [attachments addObject:log];
    }

    NSString *descText = self.descriptionView.string;
    NSString *name = self.nameField.stringValue;
    NSString *email = self.emailField.stringValue;

    __weak typeof(self) weakSelf = self;
    [[BugSplat shared] postFeedback:trimmedTitle
                        description:descText.length > 0 ? descText : nil
                           userName:name.length > 0 ? name : nil
                          userEmail:email.length > 0 ? email : nil
                             appKey:nil
                         attributes:@{ @"category": [self selectedCategory] }
                        attachments:attachments.count > 0 ? attachments : nil
                         completion:^(BugSplatFeedbackResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf setSubmitting:NO];
            if (error) {
                strongSelf.errorLabel.stringValue =
                    [NSString stringWithFormat:@"Feedback failed: %@", error.localizedDescription];
                strongSelf.errorLabel.hidden = NO;
            } else {
                NSString *detail = [NSString stringWithFormat:@"“%@”", trimmedTitle];
                [BSPActivityLog record:BSPActivityTypeFeedback detail:detail];
                [strongSelf showThanksWithResult:result];
            }
        });
    }];
}

#pragma mark - Thank-you screen

- (void)showThanksWithResult:(BugSplatFeedbackResult *)result {
    NSString *reportId = result.crashId ? result.crashId.stringValue : nil;

    self.thanksContainer = [NSView new];
    self.thanksContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.thanksContainer.wantsLayer = YES;
    self.thanksContainer.layer.backgroundColor = [BSPDemoTheme cardBg].CGColor;
    [self.view addSubview:self.thanksContainer];
    [self pinView:self.thanksContainer toEdgesOf:self.view];

    // Check circle
    NSView *circle = [NSView new];
    circle.translatesAutoresizingMaskIntoConstraints = NO;
    circle.wantsLayer = YES;
    circle.layer.backgroundColor = [[BSPDemoTheme feedbackAccent] colorWithAlphaComponent:0.14].CGColor;
    circle.layer.cornerRadius = 40;
    circle.layer.borderWidth = 1;
    circle.layer.borderColor = [[BSPDemoTheme feedbackAccent] colorWithAlphaComponent:0.35].CGColor;
    NSImageSymbolConfiguration *checkConfig = [NSImageSymbolConfiguration configurationWithPointSize:30
                                                                                              weight:NSFontWeightBold];
    NSImage *checkImage = [[NSImage imageWithSystemSymbolName:@"checkmark" accessibilityDescription:nil]
                           imageWithSymbolConfiguration:checkConfig];
    NSImageView *check = [NSImageView imageViewWithImage:checkImage];
    check.translatesAutoresizingMaskIntoConstraints = NO;
    check.contentTintColor = [BSPDemoTheme feedbackAccent];
    [circle addSubview:check];
    [NSLayoutConstraint activateConstraints:@[
        [circle.widthAnchor constraintEqualToConstant:80],
        [circle.heightAnchor constraintEqualToConstant:80],
        [check.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor],
        [check.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor],
    ]];

    NSTextField *titleLabel = [NSTextField labelWithString:@"Feedback sent. Thanks!"];
    titleLabel.font = [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
    titleLabel.textColor = [BSPDemoTheme textPrimary];
    titleLabel.alignment = NSTextAlignmentCenter;

    NSTextField *messageLabel =
        [NSTextField wrappingLabelWithString:@"Your note made it to the BugSplat team. We reply within a day."];
    messageLabel.font = [NSFont systemFontOfSize:13];
    messageLabel.textColor = [BSPDemoTheme textSecondary];
    messageLabel.alignment = NSTextAlignmentCenter;
    messageLabel.selectable = NO;

    NSView *reportRow = [self makeReportIdRow:reportId];

    NSStackView *topStack = [NSStackView stackViewWithViews:@[ circle, titleLabel, messageLabel, reportRow ]];
    topStack.translatesAutoresizingMaskIntoConstraints = NO;
    topStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    topStack.alignment = NSLayoutAttributeCenterX;
    topStack.spacing = 14;
    [topStack setCustomSpacing:18 afterView:messageLabel];

    NSView *footer = [self makeThanksFooterWithResult:result];

    [self.thanksContainer addSubview:topStack];
    [self.thanksContainer addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [topStack.centerYAnchor constraintEqualToAnchor:self.thanksContainer.centerYAnchor constant:-36],
        [topStack.leadingAnchor constraintEqualToAnchor:self.thanksContainer.leadingAnchor constant:32],
        [topStack.trailingAnchor constraintEqualToAnchor:self.thanksContainer.trailingAnchor constant:-32],
        [reportRow.leadingAnchor constraintEqualToAnchor:topStack.leadingAnchor],
        [reportRow.trailingAnchor constraintEqualToAnchor:topStack.trailingAnchor],
        [messageLabel.leadingAnchor constraintEqualToAnchor:topStack.leadingAnchor],
        [messageLabel.trailingAnchor constraintEqualToAnchor:topStack.trailingAnchor],
        [footer.leadingAnchor constraintEqualToAnchor:self.thanksContainer.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:self.thanksContainer.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:self.thanksContainer.bottomAnchor],
    ]];

    // Swap the sheet content: shrink to the thank-you size and cross-fade.
    self.thanksContainer.alphaValue = 0;
    self.preferredContentSize = NSMakeSize(kBSPFeedbackWidth, 470);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.28;
        self.formContainer.animator.alphaValue = 0;
        self.thanksContainer.animator.alphaValue = 1;
    } completionHandler:^{
        self.formContainer.hidden = YES;
    }];
}

- (NSView *)makeReportIdRow:(nullable NSString *)reportId {
    NSTextField *label = [NSTextField labelWithAttributedString:
        [[NSAttributedString alloc] initWithString:@"REPORT ID"
            attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold],
                          NSForegroundColorAttributeName: [BSPDemoTheme textTertiary],
                          NSKernAttributeName: @1.1 }]];

    NSTextField *idLabel = [NSTextField labelWithString:reportId ?: @"Unavailable"];
    idLabel.font = [NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightMedium];
    idLabel.textColor = [BSPDemoTheme textPrimary];

    NSView *spacer = [NSView new];
    NSMutableArray *rowViews = [@[ label, idLabel, spacer ] mutableCopy];
    if (reportId) {
        NSButton *copy = [NSButton buttonWithTitle:@"Copy" target:self action:@selector(copyReportId:)];
        copy.bezelStyle = NSBezelStyleRounded;
        copy.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        copy.identifier = reportId;
        [rowViews addObject:copy];
    }

    NSStackView *row = [NSStackView stackViewWithViews:rowViews];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 10;

    NSView *card = [NSView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.wantsLayer = YES;
    card.layer.backgroundColor = [BSPDemoTheme badgeBg].CGColor;
    card.layer.cornerRadius = 10;
    [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];
    return card;
}

- (void)copyReportId:(NSButton *)sender {
    NSString *reportId = sender.identifier;
    if (reportId.length == 0) return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:reportId forType:NSPasteboardTypeString];
}

- (NSView *)makeThanksFooterWithResult:(BugSplatFeedbackResult *)result {
    NSButton *dashboard = [NSButton buttonWithTitle:@"View on dashboard  ↗"
                                             target:self
                                             action:@selector(openReport:)];
    dashboard.translatesAutoresizingMaskIntoConstraints = NO;
    dashboard.bezelStyle = NSBezelStyleRounded;
    dashboard.controlSize = NSControlSizeLarge;
    dashboard.keyEquivalent = @"\r";
    dashboard.bezelColor = [BSPDemoTheme feedbackAccent];
    // Stash the result on the controller so the action can build the URL.
    self.thanksResult = result;
    [dashboard.heightAnchor constraintEqualToConstant:36].active = YES;

    NSButton *close = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeTapped)];
    close.bordered = NO;
    close.contentTintColor = [BSPDemoTheme textSecondary];
    close.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];

    NSView *poweredBy = [self makePoweredByView];

    NSStackView *stack = [NSStackView stackViewWithViews:@[ dashboard, close, poweredBy ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(14, 20, 20, 20);

    return [self footerContainerWithContent:stack stretchView:dashboard];
}

/// "Powered by BugSplat" where the word BugSplat links to bugsplat.com.
- (NSView *)makePoweredByView {
    NSTextField *prefix = [NSTextField labelWithString:@"Powered by"];
    prefix.font = [NSFont systemFontOfSize:12];
    prefix.textColor = [BSPDemoTheme textTertiary];

    NSButton *link = [NSButton buttonWithTitle:@"BugSplat" target:self action:@selector(openBugSplatSite)];
    link.bordered = NO;
    link.contentTintColor = [BSPDemoTheme link];
    link.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];

    NSStackView *row = [NSStackView stackViewWithViews:@[ prefix, link ]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 2;
    return row;
}

- (void)openBugSplatSite {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://bugsplat.com"]];
}

/// Links directly to the report by id. Feedback reports group by their (unique)
/// title, so the SDK's infoUrl resolves to a generic page — prefer the id-scoped
/// crash URL, falling back to the database dashboard.
- (void)openReport:(id)sender {
    NSURLComponents *components;
    if (self.thanksResult.crashId) {
        components = [NSURLComponents componentsWithString:@"https://app.bugsplat.com/v2/crash"];
        components.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"database" value:[self database]],
            [NSURLQueryItem queryItemWithName:@"id" value:self.thanksResult.crashId.stringValue],
        ];
    } else {
        components = [NSURLComponents componentsWithString:@"https://app.bugsplat.com/v2/dashboard"];
        components.queryItems = @[ [NSURLQueryItem queryItemWithName:@"database" value:[self database]] ];
    }
    if (components.URL) {
        [[NSWorkspace sharedWorkspace] openURL:components.URL];
    }
}

@end
