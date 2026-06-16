//
//  BSPFeedbackViewController.m
//  BugSplatTest-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BSPFeedbackViewController.h"
#import "BSPDemoTheme.h"
#import "BSPActivityLog.h"
#import <BugSplat/BugSplat.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#pragma mark - Sample log helper

/// Locates the current session's log file the app writes at launch (see AppDelegate)
/// so it can be attached to feedback when the user opts in. Each session's log is
/// named after [BugSplat shared].sessionID; since feedback is sent live during the
/// current session, the current sessionID identifies the right file.
@interface BSPSampleLog : NSObject
+ (nullable NSURL *)fileURL;
+ (nullable BugSplatAttachment *)attachment;
@end

@implementation BSPSampleLog

+ (NSURL *)fileURL {
    NSURL *appSupport = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                inDomains:NSUserDomainMask] firstObject];
    NSString *filename = [[BugSplat shared].sessionID.UUIDString stringByAppendingPathExtension:@"log"];
    return [[appSupport URLByAppendingPathComponent:@"SessionLogs" isDirectory:YES] URLByAppendingPathComponent:filename];
}

+ (BugSplatAttachment *)attachment {
    NSURL *url = [self fileURL];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    if (!data) return nil;
    return [[BugSplatAttachment alloc] initWithFilename:@"session.log"
                                         attachmentData:data
                                            contentType:@"text/plain"];
}

@end

#pragma mark - Feedback view controller

@interface BSPFeedbackViewController () <UIDocumentPickerDelegate, UITextFieldDelegate>

// Containers
@property (nonatomic, strong) UIView *formContainer;
@property (nonatomic, strong) UIView *thanksContainer;

// Form controls
@property (nonatomic, strong) UISegmentedControl *segmented;
@property (nonatomic, strong) UITextField *titleField;
@property (nonatomic, strong) UITextView *descriptionView;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *emailField;
@property (nonatomic, strong) UISwitch *includeLogsSwitch;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIActivityIndicatorView *sendSpinner;

// Attachment row
@property (nonatomic, strong) UIView *attachmentRow;
@property (nonatomic, strong) UILabel *attachmentTypeChip;
@property (nonatomic, strong) UILabel *attachmentNameLabel;
@property (nonatomic, strong) UILabel *attachmentDetailLabel;
@property (nonatomic, strong) UIButton *attachmentActionButton;

// State
@property (nonatomic, copy, nullable) NSString *pickedFileName;
@property (nonatomic, strong, nullable) NSData *pickedFileData;
@property (nonatomic, assign) BOOL submitting;

// Keyboard handling
@property (nonatomic, strong) UIScrollView *formScrollView;
@property (nonatomic, strong) NSLayoutConstraint *layoutBottomConstraint;

@end

@implementation BSPFeedbackViewController

- (NSString *)database {
    return [BugSplat shared].bugSplatDatabase ?: @"—";
}

- (NSString *)selectedCategory {
    NSArray<NSString *> *categories = @[ @"Bug", @"Feature", @"Other" ];
    NSInteger index = self.segmented.selectedSegmentIndex;
    if (index < 0 || index >= (NSInteger)categories.count) return @"Bug";
    return categories[index];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [BSPDemoTheme cardBg];
    [self buildForm];
    [self buildThanksContainer];
    [self renderAttachmentRow];
    [self updateSendEnabled];
    [self installKeyboardHandling];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Only when the sheet is actually going away - not when it is merely
    // covered by a controller it presented (e.g. the document picker).
    if (self.isBeingDismissed && self.onDismiss) self.onDismiss();
}

#pragma mark - Form layout

- (void)buildForm {
    self.formContainer = [UIView new];
    self.formContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.formContainer];
    [NSLayoutConstraint activateConstraints:@[
        [self.formContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.formContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.formContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.formContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIView *header = [self makeHeaderWithTitle:@"Send feedback"];
    UIView *headerDivider = [self makeDivider];
    UIView *footer = [self makeFormFooter];

    UIScrollView *scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.formScrollView = scrollView;

    UIStackView *fields = [UIStackView new];
    fields.translatesAutoresizingMaskIntoConstraints = NO;
    fields.axis = UILayoutConstraintAxisVertical;
    fields.spacing = 18;
    fields.alignment = UIStackViewAlignmentFill;

    self.segmented = [[UISegmentedControl alloc] initWithItems:@[ @"Bug", @"Feature", @"Other" ]];
    self.segmented.selectedSegmentIndex = 0;
    [fields addArrangedSubview:self.segmented];

    self.titleField = [self makeTextField];
    [fields addArrangedSubview:[self makeFieldWithLabel:@"Title" required:YES input:[self boxedInput:self.titleField]]];

    self.descriptionView = [UITextView new];
    self.descriptionView.font = [UIFont systemFontOfSize:15];
    self.descriptionView.textColor = [BSPDemoTheme textPrimary];
    self.descriptionView.backgroundColor = UIColor.clearColor;
    self.descriptionView.scrollEnabled = NO;
    self.descriptionView.textContainerInset = UIEdgeInsetsMake(7, 8, 7, 8);
    [self.descriptionView.heightAnchor constraintGreaterThanOrEqualToConstant:92].active = YES;
    [fields addArrangedSubview:[self makeFieldWithLabel:@"Description" required:NO input:[self boxedInput:self.descriptionView]]];

    self.nameField = [self makeTextField];
    self.nameField.textContentType = UITextContentTypeName;
    [fields addArrangedSubview:[self makeFieldWithLabel:@"Name" required:NO input:[self boxedInput:self.nameField]]];

    self.emailField = [self makeTextField];
    self.emailField.textContentType = UITextContentTypeEmailAddress;
    self.emailField.keyboardType = UIKeyboardTypeEmailAddress;
    self.emailField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [fields addArrangedSubview:[self makeFieldWithLabel:@"Email" required:NO input:[self boxedInput:self.emailField]]];

    [self buildAttachmentRow];
    [fields addArrangedSubview:[self makeFieldWithLabel:@"Attachment" required:NO input:self.attachmentRow]];

    [fields addArrangedSubview:[self makeIncludeLogsRow]];

    self.errorLabel = [UILabel new];
    self.errorLabel.font = [UIFont systemFontOfSize:13];
    self.errorLabel.textColor = [BSPDemoTheme asterisk];
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [fields addArrangedSubview:self.errorLabel];

    [scrollView addSubview:fields];

    UIStackView *layout = [[UIStackView alloc] initWithArrangedSubviews:@[ header, headerDivider, scrollView, footer ]];
    layout.translatesAutoresizingMaskIntoConstraints = NO;
    layout.axis = UILayoutConstraintAxisVertical;
    layout.alignment = UIStackViewAlignmentFill;
    [self.formContainer addSubview:layout];

    // Held onto so the keyboard handler can lift the whole layout (scroll view
    // + footer) above the keyboard.
    self.layoutBottomConstraint = [layout.bottomAnchor constraintEqualToAnchor:self.formContainer.bottomAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [layout.topAnchor constraintEqualToAnchor:self.formContainer.safeAreaLayoutGuide.topAnchor],
        [layout.leadingAnchor constraintEqualToAnchor:self.formContainer.leadingAnchor],
        [layout.trailingAnchor constraintEqualToAnchor:self.formContainer.trailingAnchor],
        self.layoutBottomConstraint,

        [fields.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:20],
        [fields.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-20],
        [fields.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor constant:20],
        [fields.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor constant:-20],
        [fields.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor constant:-40],
    ]];
}

- (UIView *)makeHeaderWithTitle:(NSString *)title {
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    label.textColor = [BSPDemoTheme textPrimary];
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = [BSPDemoTheme textSecondary];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];

    UIView *bar = [UIView new];
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

- (UIView *)makeFormFooter {
    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton setTitle:@"Send feedback  →" forState:UIControlStateNormal];
    self.sendButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.sendButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.sendButton.backgroundColor = [BSPDemoTheme feedbackAccent];
    self.sendButton.layer.cornerRadius = 12;
    self.sendButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.sendButton.heightAnchor constraintEqualToConstant:52].active = YES;
    [self.sendButton addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];

    self.sendSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.sendSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendSpinner.color = UIColor.whiteColor;
    self.sendSpinner.hidesWhenStopped = YES;
    [self.sendButton addSubview:self.sendSpinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.sendSpinner.centerXAnchor constraintEqualToAnchor:self.sendButton.centerXAnchor],
        [self.sendSpinner.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
    ]];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ self.sendButton ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.alignment = UIStackViewAlignmentFill;
    stack.layoutMarginsRelativeArrangement = YES;
    stack.layoutMargins = UIEdgeInsetsMake(20, 20, 20, 20);

    return [self footerContainerWithContent:stack];
}

- (UIView *)footerContainerWithContent:(UIView *)content {
    UIView *container = [UIView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [BSPDemoTheme footerBg];
    UIView *divider = [self makeDivider];
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
    return container;
}

- (void)buildAttachmentRow {
    self.attachmentRow = [UIView new];
    self.attachmentRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentRow.backgroundColor = [BSPDemoTheme cardBg];
    self.attachmentRow.layer.cornerRadius = 10;
    self.attachmentRow.layer.cornerCurve = kCACornerCurveContinuous;
    self.attachmentRow.layer.borderColor = [BSPDemoTheme cardStroke].CGColor;
    self.attachmentRow.layer.borderWidth = 1;

    self.attachmentTypeChip = [UILabel new];
    self.attachmentTypeChip.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentTypeChip.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.attachmentTypeChip.textColor = [BSPDemoTheme textSecondary];
    self.attachmentTypeChip.textAlignment = NSTextAlignmentCenter;
    self.attachmentTypeChip.backgroundColor = [BSPDemoTheme badgeBg];
    self.attachmentTypeChip.layer.cornerRadius = 8;
    self.attachmentTypeChip.layer.masksToBounds = YES;

    self.attachmentNameLabel = [UILabel new];
    self.attachmentNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentNameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.attachmentNameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    self.attachmentDetailLabel = [UILabel new];
    self.attachmentDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentDetailLabel.font = [UIFont systemFontOfSize:12];
    self.attachmentDetailLabel.textColor = [BSPDemoTheme textTertiary];

    self.attachmentActionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.attachmentActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentActionButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.attachmentActionButton setTitleColor:[BSPDemoTheme link] forState:UIControlStateNormal];
    [self.attachmentActionButton addTarget:self action:@selector(pickFileTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.attachmentActionButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[ self.attachmentNameLabel, self.attachmentDetailLabel ]];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 2;

    [self.attachmentRow addSubview:self.attachmentTypeChip];
    [self.attachmentRow addSubview:textStack];
    [self.attachmentRow addSubview:self.attachmentActionButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.attachmentTypeChip.leadingAnchor constraintEqualToAnchor:self.attachmentRow.leadingAnchor constant:12],
        [self.attachmentTypeChip.centerYAnchor constraintEqualToAnchor:self.attachmentRow.centerYAnchor],
        [self.attachmentTypeChip.widthAnchor constraintEqualToConstant:44],
        [self.attachmentTypeChip.heightAnchor constraintEqualToConstant:44],

        [textStack.leadingAnchor constraintEqualToAnchor:self.attachmentTypeChip.trailingAnchor constant:12],
        [textStack.centerYAnchor constraintEqualToAnchor:self.attachmentRow.centerYAnchor],

        [self.attachmentActionButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:textStack.trailingAnchor constant:8],
        [self.attachmentActionButton.trailingAnchor constraintEqualToAnchor:self.attachmentRow.trailingAnchor constant:-12],
        [self.attachmentActionButton.centerYAnchor constraintEqualToAnchor:self.attachmentRow.centerYAnchor],

        [self.attachmentRow.heightAnchor constraintGreaterThanOrEqualToConstant:68],
    ]];
}

- (void)renderAttachmentRow {
    if (self.pickedFileName.length > 0 && self.pickedFileData) {
        NSString *ext = self.pickedFileName.pathExtension.uppercaseString;
        self.attachmentTypeChip.text = ext.length > 0 ? ext : @"FILE";
        self.attachmentTypeChip.hidden = NO;
        self.attachmentNameLabel.text = self.pickedFileName;
        self.attachmentNameLabel.textColor = [BSPDemoTheme textPrimary];
        self.attachmentDetailLabel.text = [NSByteCountFormatter stringFromByteCount:(long long)self.pickedFileData.length
                                                                         countStyle:NSByteCountFormatterCountStyleFile];
        self.attachmentDetailLabel.hidden = NO;
        [self.attachmentActionButton setTitle:@"Replace" forState:UIControlStateNormal];
    } else {
        self.attachmentTypeChip.hidden = YES;
        self.attachmentNameLabel.text = @"No file selected";
        self.attachmentNameLabel.textColor = [BSPDemoTheme textTertiary];
        self.attachmentDetailLabel.hidden = YES;
        [self.attachmentActionButton setTitle:@"Add" forState:UIControlStateNormal];
    }
}

- (UIView *)makeIncludeLogsRow {
    UILabel *title = [UILabel new];
    title.text = @"Include logs";
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    title.textColor = [BSPDemoTheme textPrimary];

    UILabel *subtitle = [UILabel new];
    subtitle.text = @"Attach this session's log file";
    subtitle.font = [UIFont systemFontOfSize:12];
    subtitle.textColor = [BSPDemoTheme textTertiary];

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[ title, subtitle ]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 2;

    self.includeLogsSwitch = [UISwitch new];
    self.includeLogsSwitch.on = YES;
    self.includeLogsSwitch.onTintColor = [BSPDemoTheme feedbackAccent];
    [self.includeLogsSwitch setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ textStack, self.includeLogsSwitch ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    return row;
}

#pragma mark - Field helpers

- (UITextField *)makeTextField {
    UITextField *field = [UITextField new];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = [UIFont systemFontOfSize:15];
    field.textColor = [BSPDemoTheme textPrimary];
    field.borderStyle = UITextBorderStyleNone;
    field.delegate = self;
    [field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
    return field;
}

/// Wraps an input view in a rounded, outlined box.
- (UIView *)boxedInput:(UIView *)input {
    UIView *box = [UIView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.backgroundColor = [BSPDemoTheme cardBg];
    box.layer.cornerRadius = 10;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.layer.borderColor = [BSPDemoTheme cardStroke].CGColor;
    box.layer.borderWidth = 1;
    input.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:input];
    BOOL isTextView = [input isKindOfClass:[UITextView class]];
    CGFloat vInset = isTextView ? 0 : 11;
    CGFloat hInset = isTextView ? 0 : 12;
    [NSLayoutConstraint activateConstraints:@[
        [input.topAnchor constraintEqualToAnchor:box.topAnchor constant:vInset],
        [input.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-vInset],
        [input.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:hInset],
        [input.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-hInset],
    ]];
    if (!isTextView) {
        [input.heightAnchor constraintGreaterThanOrEqualToConstant:22].active = YES;
    }
    return box;
}

/// A labeled field: a header row (label + red asterisk or "optional") above the input.
- (UIView *)makeFieldWithLabel:(NSString *)label required:(BOOL)required input:(UIView *)input {
    UILabel *labelView = [UILabel new];
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc]
        initWithString:label
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],
                          NSForegroundColorAttributeName: [BSPDemoTheme textPrimary] }];
    if (required) {
        [attributed appendAttributedString:[[NSAttributedString alloc]
            initWithString:@" *"
                attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],
                              NSForegroundColorAttributeName: [BSPDemoTheme asterisk] }]];
    }
    labelView.attributedText = attributed;

    UIView *headerRow;
    if (required) {
        headerRow = labelView;
    } else {
        UILabel *optional = [UILabel new];
        optional.text = @"optional";
        optional.font = [UIFont systemFontOfSize:13];
        optional.textColor = [BSPDemoTheme textTertiary];
        UIView *spacer = [UIView new];
        [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ labelView, spacer, optional ]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentFirstBaseline;
        headerRow = row;
    }

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ headerRow, input ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.alignment = UIStackViewAlignmentFill;
    return stack;
}

- (UIView *)makeDivider {
    UIView *divider = [UIView new];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [BSPDemoTheme cardStroke];
    [divider.heightAnchor constraintEqualToConstant:1].active = YES;
    return divider;
}

#pragma mark - Keyboard handling

/// Lifts the form (footer + scroll view) above the keyboard and lets a tap
/// outside any field dismiss it.
- (void)installKeyboardHandling {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardFrameWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;  // let buttons/controls still receive the tap
    [self.view addGestureRecognizer:tap];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)keyboardFrameWillChange:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGRect endFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[info[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    CGRect endInView = [self.view convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(endInView));
    self.layoutBottomConstraint.constant = -overlap;

    [UIView animateWithDuration:duration
                          delay:0
                        options:(UIViewAnimationOptions)(curve << 16)
                     animations:^{ [self.view layoutIfNeeded]; }
                     completion:^(BOOL finished) { [self scrollActiveFieldToVisible]; }];
}

/// Keeps the focused field visible after the scroll view shrinks for the keyboard.
- (void)scrollActiveFieldToVisible {
    UIView *active = nil;
    for (UIView *field in @[ self.titleField, self.descriptionView, self.nameField, self.emailField ]) {
        if (field.isFirstResponder) { active = field; break; }
    }
    if (!active) return;
    CGRect rect = [self.formScrollView convertRect:active.bounds fromView:active];
    [self.formScrollView scrollRectToVisible:CGRectInset(rect, 0, -16) animated:YES];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Form actions

- (void)textChanged {
    [self updateSendEnabled];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateSendEnabled {
    NSString *trimmed = [self.titleField.text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL enabled = trimmed.length > 0 && !self.submitting;
    self.sendButton.enabled = enabled;
    self.sendButton.alpha = enabled ? 1.0 : 0.45;
}

- (void)pickFileTapped {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[ UTTypeItem ] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)setSubmitting:(BOOL)submitting {
    _submitting = submitting;
    if (submitting) {
        [self.sendButton setTitle:@"" forState:UIControlStateNormal];
        [self.sendSpinner startAnimating];
    } else {
        [self.sendButton setTitle:@"Send feedback  →" forState:UIControlStateNormal];
        [self.sendSpinner stopAnimating];
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
    NSString *trimmedTitle = [self.titleField.text stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
    if (self.includeLogsSwitch.isOn) {
        BugSplatAttachment *log = [BSPSampleLog attachment];
        if (log) [attachments addObject:log];
    }

    NSString *descText = self.descriptionView.text;
    NSString *name = self.nameField.text;
    NSString *email = self.emailField.text;

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
                strongSelf.errorLabel.text = [NSString stringWithFormat:@"Feedback failed: %@",
                                              error.localizedDescription];
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

- (void)buildThanksContainer {
    self.thanksContainer = [UIView new];
    self.thanksContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.thanksContainer.backgroundColor = [BSPDemoTheme cardBg];
    self.thanksContainer.hidden = YES;
    [self.view addSubview:self.thanksContainer];
    [NSLayoutConstraint activateConstraints:@[
        [self.thanksContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.thanksContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.thanksContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.thanksContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)showThanksWithResult:(BugSplatFeedbackResult *)result {
    NSString *reportId = result.crashId ? result.crashId.stringValue : nil;

    UIView *circle = [UIView new];
    circle.translatesAutoresizingMaskIntoConstraints = NO;
    circle.backgroundColor = [[BSPDemoTheme feedbackAccent] colorWithAlphaComponent:0.14];
    circle.layer.cornerRadius = 42;
    circle.layer.borderColor = [[BSPDemoTheme feedbackAccent] colorWithAlphaComponent:0.35].CGColor;
    circle.layer.borderWidth = 1;
    UIImageConfiguration *checkConfig = [UIImageSymbolConfiguration configurationWithPointSize:32
                                                                                       weight:UIImageSymbolWeightBold];
    UIImageView *check = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"checkmark" withConfiguration:checkConfig]];
    check.tintColor = [BSPDemoTheme feedbackAccent];
    check.translatesAutoresizingMaskIntoConstraints = NO;
    [circle addSubview:check];
    [NSLayoutConstraint activateConstraints:@[
        [circle.widthAnchor constraintEqualToConstant:84],
        [circle.heightAnchor constraintEqualToConstant:84],
        [check.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor],
        [check.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor],
    ]];
    UIView *circleWrap = [UIView new];
    [circleWrap addSubview:circle];
    [NSLayoutConstraint activateConstraints:@[
        [circle.topAnchor constraintEqualToAnchor:circleWrap.topAnchor],
        [circle.bottomAnchor constraintEqualToAnchor:circleWrap.bottomAnchor],
        [circle.centerXAnchor constraintEqualToAnchor:circleWrap.centerXAnchor],
    ]];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = @"Feedback sent. Thanks!";
    titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    titleLabel.textColor = [BSPDemoTheme textPrimary];
    titleLabel.textAlignment = NSTextAlignmentCenter;

    UILabel *messageLabel = [UILabel new];
    messageLabel.text = @"Your note made it to the BugSplat team. We reply within a day.";
    messageLabel.font = [UIFont systemFontOfSize:15];
    messageLabel.textColor = [BSPDemoTheme textSecondary];
    messageLabel.textAlignment = NSTextAlignmentCenter;
    messageLabel.numberOfLines = 0;

    UIView *reportRow = [self makeReportIdRow:reportId];

    UIStackView *topStack = [[UIStackView alloc] initWithArrangedSubviews:@[ circleWrap, titleLabel, messageLabel, reportRow ]];
    topStack.translatesAutoresizingMaskIntoConstraints = NO;
    topStack.axis = UILayoutConstraintAxisVertical;
    topStack.alignment = UIStackViewAlignmentFill;
    topStack.spacing = 16;
    [topStack setCustomSpacing:20 afterView:messageLabel];

    UIView *footer = [self makeThanksFooterWithResult:result];

    [self.thanksContainer addSubview:topStack];
    [self.thanksContainer addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [topStack.centerYAnchor constraintEqualToAnchor:self.thanksContainer.centerYAnchor constant:-40],
        [topStack.leadingAnchor constraintEqualToAnchor:self.thanksContainer.leadingAnchor constant:24],
        [topStack.trailingAnchor constraintEqualToAnchor:self.thanksContainer.trailingAnchor constant:-24],

        [footer.leadingAnchor constraintEqualToAnchor:self.thanksContainer.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:self.thanksContainer.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:self.thanksContainer.bottomAnchor],
    ]];

    self.thanksContainer.alpha = 0;
    self.thanksContainer.hidden = NO;
    [UIView transitionWithView:self.view
                      duration:0.3
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        self.formContainer.hidden = YES;
        self.thanksContainer.alpha = 1;
    } completion:nil];
}

- (UIView *)makeReportIdRow:(nullable NSString *)reportId {
    UILabel *label = [UILabel new];
    label.attributedText = [[NSAttributedString alloc]
        initWithString:@"REPORT ID"
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold],
                          NSForegroundColorAttributeName: [BSPDemoTheme textTertiary],
                          NSKernAttributeName: @1.1 }];

    UILabel *idLabel = [UILabel new];
    idLabel.text = reportId ?: @"Unavailable";
    idLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightMedium];
    idLabel.textColor = [BSPDemoTheme textPrimary];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ label, idLabel ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    if (reportId) {
        UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
        [copy setTitle:@"Copy" forState:UIControlStateNormal];
        [copy setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
        copy.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        copy.tintColor = [BSPDemoTheme textSecondary];
        [copy setTitleColor:[BSPDemoTheme textSecondary] forState:UIControlStateNormal];
        copy.backgroundColor = [BSPDemoTheme cardBg];
        copy.layer.cornerRadius = 8;
        copy.layer.borderColor = [BSPDemoTheme cardStroke].CGColor;
        copy.layer.borderWidth = 1;
        copy.contentEdgeInsets = UIEdgeInsetsMake(7, 12, 7, 12);
        copy.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
        [copy setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [copy addAction:[UIAction actionWithHandler:^(UIAction *action) {
            UIPasteboard.generalPasteboard.string = reportId;
        }] forControlEvents:UIControlEventTouchUpInside];
        UIView *spacer = [UIView new];
        [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [row addArrangedSubview:spacer];
        [row addArrangedSubview:copy];
    }

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [BSPDemoTheme badgeBg];
    card.layer.cornerRadius = 12;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];
    return card;
}

- (UIView *)makeThanksFooterWithResult:(BugSplatFeedbackResult *)result {
    UIButton *dashboard = [UIButton buttonWithType:UIButtonTypeSystem];
    dashboard.translatesAutoresizingMaskIntoConstraints = NO;
    [dashboard setTitle:@"View on dashboard  ↗" forState:UIControlStateNormal];
    dashboard.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [dashboard setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    dashboard.backgroundColor = [BSPDemoTheme feedbackAccent];
    dashboard.layer.cornerRadius = 12;
    dashboard.layer.cornerCurve = kCACornerCurveContinuous;
    [dashboard.heightAnchor constraintEqualToConstant:52].active = YES;
    [dashboard addAction:[UIAction actionWithHandler:^(UIAction *action) {
        [self openReportWithResult:result];
    }] forControlEvents:UIControlEventTouchUpInside];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"Close" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [close setTitleColor:[BSPDemoTheme textSecondary] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ dashboard, close, [self makePoweredByView] ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.alignment = UIStackViewAlignmentFill;
    stack.layoutMarginsRelativeArrangement = YES;
    stack.layoutMargins = UIEdgeInsetsMake(14, 20, 20, 20);

    return [self footerContainerWithContent:stack];
}

/// "Powered by BugSplat" where the word BugSplat links to bugsplat.com.
- (UIView *)makePoweredByView {
    UILabel *prefix = [UILabel new];
    prefix.text = @"Powered by";
    prefix.font = [UIFont systemFontOfSize:13];
    prefix.textColor = [BSPDemoTheme textTertiary];

    UIButton *link = [UIButton buttonWithType:UIButtonTypeSystem];
    [link setTitle:@"BugSplat" forState:UIControlStateNormal];
    link.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [link setTitleColor:[BSPDemoTheme link] forState:UIControlStateNormal];
    link.contentEdgeInsets = UIEdgeInsetsZero;
    [link addAction:[UIAction actionWithHandler:^(UIAction *action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://bugsplat.com"]
                                           options:@{} completionHandler:nil];
    }] forControlEvents:UIControlEventTouchUpInside];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ prefix, link ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 4;
    row.alignment = UIStackViewAlignmentCenter;

    UIView *leftSpacer = [UIView new];
    UIView *rightSpacer = [UIView new];
    UIStackView *centered = [[UIStackView alloc] initWithArrangedSubviews:@[ leftSpacer, row, rightSpacer ]];
    centered.axis = UILayoutConstraintAxisHorizontal;
    centered.distribution = UIStackViewDistributionEqualCentering;
    return centered;
}

/// Links directly to the report by id. Feedback reports group by their (unique)
/// title, so the SDK's infoUrl resolves to a generic page — prefer the id-scoped
/// crash URL, falling back to the database dashboard.
- (void)openReportWithResult:(BugSplatFeedbackResult *)result {
    NSURLComponents *components;
    if (result.crashId) {
        components = [NSURLComponents componentsWithString:@"https://app.bugsplat.com/v2/crash"];
        components.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"database" value:[self database]],
            [NSURLQueryItem queryItemWithName:@"id" value:result.crashId.stringValue],
        ];
    } else {
        components = [NSURLComponents componentsWithString:@"https://app.bugsplat.com/v2/dashboard"];
        components.queryItems = @[ [NSURLQueryItem queryItemWithName:@"database" value:[self database]] ];
    }
    NSURL *url = components.URL;
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (data) {
        self.pickedFileData = data;
        self.pickedFileName = url.lastPathComponent;
        [self renderAttachmentRow];
    } else {
        self.errorLabel.text = [NSString stringWithFormat:@"Couldn't read the selected file: %@",
                                error.localizedDescription];
        self.errorLabel.hidden = NO;
    }
}

@end
