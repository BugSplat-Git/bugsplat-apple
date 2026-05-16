//
//  ViewController.m
//  BugSplatTest-UIKit-ObjC
//
//  Programmatic UIKit port of the SwiftUI demo screen. Mirrors layout, copy,
//  palette, and behavior from BugSplatTest-SwiftUI/ContentView.swift.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "ViewController.h"
#import <BugSplat/BugSplat.h>

#import "BSPActivityLog.h"
#import "BSPDemoTheme.h"
#import "BSPDemoViews.h"

@interface ViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// Title row
@property (nonatomic, strong) BSPDatabaseBadge *databaseBadge;

// Recent activity card and its dynamic content area.
@property (nonatomic, strong) UIView *recentActivityCard;
@property (nonatomic, strong) UIStackView *recentActivityStack;
@property (nonatomic, strong) UILabel *recentActivityEmptyLabel;

// Footer line at the bottom of the scroll view.
@property (nonatomic, strong) UILabel *footerLabel;

// Sticky session-only feedback status message (matches SwiftUI feedbackStatus).
@property (nonatomic, copy, nullable) NSString *feedbackStatus;

@end

@implementation ViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    // Attributes can be set any time and can contain dynamic values. Attributes
    // set in this app session only appear if the session terminates with a
    // crash report being sent.
    [[BugSplat shared] setValue:[[NSDate now] description] forAttribute:@"ViewDidLoadDateTime"];

    self.view.backgroundColor = BSPDemoTheme.screenBg;

    [self buildLayout];
    [self refreshRecentActivity];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshRecentActivity];
}

- (void)applicationDidBecomeActive:(NSNotification *)note {
    [self refreshRecentActivity];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Forward shake gestures so the BugSplat feedback UI continues to surface on
// shake the way the SwiftUI sample's footer copy suggests.
- (BOOL)canBecomeFirstResponder { return YES; }

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
}

#pragma mark - Derived data

- (NSString *)database {
    NSString *db = [[BugSplat shared] bugSplatDatabase];
    return db.length > 0 ? db : @"—";
}

- (NSString *)sdkVersion {
    NSBundle *bundle = [NSBundle bundleForClass:[BugSplat class]];
    NSString *v = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [NSString stringWithFormat:@"v%@", v ?: @"—"];
}

#pragma mark - Layout construction

- (void)buildLayout {
    // Scroll container.
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];

    // Outer vertical stack for the entire screen content.
    UIStackView *outer = [[UIStackView alloc] init];
    outer.translatesAutoresizingMaskIntoConstraints = NO;
    outer.axis = UILayoutConstraintAxisVertical;
    outer.alignment = UIStackViewAlignmentFill;
    outer.spacing = 0;
    [self.contentView addSubview:outer];

    [NSLayoutConstraint activateConstraints:@[
        [outer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:20],
        [outer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [outer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [outer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-32],
    ]];

    // Top bar: wordmark, spacer, version, status pill.
    UIView *topBar = [self buildTopBar];
    [outer addArrangedSubview:topBar];

    // Title row.
    UIView *titleRow = [self buildTitleRow];
    [outer addArrangedSubview:titleRow];
    [outer setCustomSpacing:22 afterView:topBar];

    // Subtitle line.
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"Trigger an event. We catch it, group it, route it to your dashboard.";
    subtitle.font = [UIFont systemFontOfSize:15];
    subtitle.textColor = BSPDemoTheme.textSecondary;
    subtitle.numberOfLines = 0;
    [outer addArrangedSubview:subtitle];
    [outer setCustomSpacing:6 afterView:titleRow];

    // Section header "TRIGGER AN EVENT".
    UILabel *triggerHeader = [self sectionHeaderLabelWithText:@"TRIGGER AN EVENT"];
    [outer addArrangedSubview:triggerHeader];
    [outer setCustomSpacing:22 afterView:subtitle];

    // Four event cards in a 12pt-spaced vertical stack.
    UIStackView *cards = [[UIStackView alloc] init];
    cards.axis = UILayoutConstraintAxisVertical;
    cards.spacing = 12;
    cards.alignment = UIStackViewAlignmentFill;

    BSPEventCardView *crashCard = [[BSPEventCardView alloc] initWithIconName:@"splat_crash"
                                                                       title:@"Crash"
                                                                    subtitle:@"Native crash · stack + threads + memory"];
    [crashCard addTarget:self action:@selector(triggerCrash) forControlEvents:UIControlEventTouchUpInside];
    [cards addArrangedSubview:crashCard];

    BSPEventCardView *errorCard = [[BSPEventCardView alloc] initWithIconName:@"splat_error"
                                                                       title:@"Non-Crash Error"
                                                                    subtitle:@"Exception caught · app keeps running"];
    [errorCard addTarget:self action:@selector(triggerNonCrashError) forControlEvents:UIControlEventTouchUpInside];
    [cards addArrangedSubview:errorCard];

    BSPEventCardView *feedbackCard = [[BSPEventCardView alloc] initWithIconName:@"splat_feedback"
                                                                          title:@"User Feedback"
                                                                       subtitle:@"Open the feedback sheet"];
    [feedbackCard addTarget:self action:@selector(showFeedbackDialog) forControlEvents:UIControlEventTouchUpInside];
    [cards addArrangedSubview:feedbackCard];

    BSPEventCardView *hangCard = [[BSPEventCardView alloc] initWithIconName:@"splat_hang"
                                                                      title:@"Hang"
                                                                   subtitle:@"Freeze main thread for 8 seconds"];
    [hangCard addTarget:self action:@selector(showHangConfirm) forControlEvents:UIControlEventTouchUpInside];
    [cards addArrangedSubview:hangCard];

    [outer addArrangedSubview:cards];
    [outer setCustomSpacing:12 afterView:triggerHeader];

    // Recent activity card.
    self.recentActivityCard = [self buildRecentActivityCard];
    [outer addArrangedSubview:self.recentActivityCard];
    [outer setCustomSpacing:18 afterView:cards];

    // Footer.
    self.footerLabel = [[UILabel alloc] init];
    self.footerLabel.font = [UIFont systemFontOfSize:13];
    self.footerLabel.textColor = BSPDemoTheme.textTertiary;
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    self.footerLabel.numberOfLines = 0;
    self.footerLabel.text = @"Shake the device to send feedback anytime.";
    [outer addArrangedSubview:self.footerLabel];
    [outer setCustomSpacing:18 afterView:self.recentActivityCard];
}

- (UIView *)buildTopBar {
    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    UIImage *wordmarkImage = [UIImage imageNamed:@"bugsplat_wordmark"];
    UIImageView *wordmark = [[UIImageView alloc] initWithImage:wordmarkImage];
    wordmark.translatesAutoresizingMaskIntoConstraints = NO;
    wordmark.contentMode = UIViewContentModeScaleAspectFit;
    // Pin to intrinsic aspect ratio so the view doesn't stretch horizontally;
    // otherwise scaleAspectFit centers the image inside a wide frame and the
    // logo visually drifts toward the bar's center instead of hugging leading.
    [wordmark setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [bar addSubview:wordmark];

    UILabel *version = [[UILabel alloc] init];
    version.translatesAutoresizingMaskIntoConstraints = NO;
    version.text = [self sdkVersion];
    UIFont *mono = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    version.font = mono;
    version.textColor = BSPDemoTheme.textSecondary;
    [version setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [bar addSubview:version];

    BSPStatusPill *pill = [[BSPStatusPill alloc] initWithConnected:YES];
    [pill setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [bar addSubview:pill];

    [NSLayoutConstraint activateConstraints:@[
        [wordmark.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [wordmark.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [wordmark.heightAnchor constraintEqualToConstant:28],
        [wordmark.widthAnchor constraintEqualToAnchor:wordmark.heightAnchor
                                            multiplier:(wordmarkImage.size.height > 0
                                                        ? wordmarkImage.size.width / wordmarkImage.size.height
                                                        : 1.0)],

        [pill.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [pill.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [version.trailingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:-10],
        [version.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [version.leadingAnchor constraintGreaterThanOrEqualToAnchor:wordmark.trailingAnchor constant:10],

        [bar.heightAnchor constraintGreaterThanOrEqualToConstant:32],
    ]];

    return bar;
}

- (UIView *)buildTitleRow {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"BugSplat SDK · Demo";
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    title.textColor = BSPDemoTheme.textPrimary;
    [title setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [title setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [row addSubview:title];

    self.databaseBadge = [[BSPDatabaseBadge alloc] initWithText:[self database]];
    [self.databaseBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [row addSubview:self.databaseBadge];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [title.topAnchor constraintEqualToAnchor:row.topAnchor],
        [title.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],

        [self.databaseBadge.leadingAnchor constraintEqualToAnchor:title.trailingAnchor constant:10],
        // Align the badge's vertical center with the title's vertical center
        // so the small pill sits beside the large title text, not above/below.
        [self.databaseBadge.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [self.databaseBadge.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor],
    ]];

    return row;
}

- (UILabel *)sectionHeaderLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.textColor = BSPDemoTheme.textTertiary;
    NSMutableAttributedString *str = [[NSMutableAttributedString alloc]
        initWithString:text
            attributes:@{ NSKernAttributeName: @(1.2) }];
    label.attributedText = str;
    return label;
}

- (UIView *)buildRecentActivityCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = BSPDemoTheme.cardBg;
    card.layer.cornerRadius = 14;
    card.layer.borderWidth = 1;
    card.layer.borderColor = BSPDemoTheme.cardStroke.CGColor;

    // Header row inside the card: section header + dashboard link.
    UIView *headerRow = [[UIView alloc] init];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:headerRow];

    UILabel *header = [self sectionHeaderLabelWithText:@"RECENT ACTIVITY"];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:header];

    UIButton *link = [UIButton buttonWithType:UIButtonTypeSystem];
    link.translatesAutoresizingMaskIntoConstraints = NO;
    [link setTitle:@"View dashboard ↗" forState:UIControlStateNormal];
    link.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [link setTitleColor:BSPDemoTheme.link forState:UIControlStateNormal];
    [link addTarget:self action:@selector(openDashboard) forControlEvents:UIControlEventTouchUpInside];
    [headerRow addSubview:link];

    // Stack that holds either the empty-state label or the activity rows.
    self.recentActivityStack = [[UIStackView alloc] init];
    self.recentActivityStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.recentActivityStack.axis = UILayoutConstraintAxisVertical;
    self.recentActivityStack.alignment = UIStackViewAlignmentFill;
    self.recentActivityStack.spacing = 10;
    [card addSubview:self.recentActivityStack];

    self.recentActivityEmptyLabel = [[UILabel alloc] init];
    self.recentActivityEmptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.recentActivityEmptyLabel.text = @"No events yet — tap a card above to get started.";
    self.recentActivityEmptyLabel.font = [UIFont systemFontOfSize:14];
    self.recentActivityEmptyLabel.textColor = BSPDemoTheme.textTertiary;
    self.recentActivityEmptyLabel.numberOfLines = 0;

    [NSLayoutConstraint activateConstraints:@[
        [headerRow.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [headerRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [headerRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [header.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor],
        [header.topAnchor constraintEqualToAnchor:headerRow.topAnchor],
        [header.bottomAnchor constraintEqualToAnchor:headerRow.bottomAnchor],
        [header.centerYAnchor constraintEqualToAnchor:link.centerYAnchor],

        [link.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor],
        [link.topAnchor constraintGreaterThanOrEqualToAnchor:headerRow.topAnchor],
        [link.bottomAnchor constraintLessThanOrEqualToAnchor:headerRow.bottomAnchor],

        [self.recentActivityStack.topAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:14],
        [self.recentActivityStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.recentActivityStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.recentActivityStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
    ]];

    return card;
}

#pragma mark - Recent activity

- (void)refreshRecentActivity {
    // Remove every arranged subview, then either drop the empty label in or
    // append a row per recorded entry.
    NSArray<UIView *> *existing = [self.recentActivityStack.arrangedSubviews copy];
    for (UIView *v in existing) {
        [self.recentActivityStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    NSArray<NSDictionary *> *entries = [BSPActivityLog all];
    if (entries.count == 0) {
        [self.recentActivityStack addArrangedSubview:self.recentActivityEmptyLabel];
        return;
    }

    for (NSDictionary *entry in entries) {
        NSString *type = entry[BSPActivityEntryKeyType];
        NSString *detail = entry[BSPActivityEntryKeyDetail];
        NSNumber *ts = entry[BSPActivityEntryKeyTimestamp];
        BSPRecentActivityRow *row = [[BSPRecentActivityRow alloc] initWithType:type
                                                                        detail:detail
                                                                     timestamp:ts.doubleValue];
        [self.recentActivityStack addArrangedSubview:row];
    }
}

#pragma mark - Footer

- (void)setFeedbackStatus:(NSString *)feedbackStatus {
    _feedbackStatus = [feedbackStatus copy];
    self.footerLabel.text = feedbackStatus.length > 0
        ? feedbackStatus
        : @"Shake the device to send feedback anytime.";
}

#pragma mark - Actions

- (void)triggerCrash {
    // Record synchronously before the crash so the entry survives process
    // death and shows up when the app relaunches.
    [BSPActivityLog record:BSPActivityTypeCrash detail:@"Native crash triggered"];
    [self refreshRecentActivity];
    // Null pointer dereference - guaranteed SIGSEGV. Sending an ObjC message
    // to nil silently returns 0, so a plain C deref is what actually crashes.
    volatile int *ptr = NULL;
    *ptr = 42;
}

- (void)triggerNonCrashError {
    // ObjC lets us actually catch a real NSException — out-of-bounds is the
    // tidiest one to provoke. Catch, then log the exception name in the entry
    // detail, matching the SwiftUI sample's "NSInvalidArgumentException caught"
    // shape with the real exception name we observed.
    @try {
        NSArray *empty = @[];
        (void)[empty objectAtIndex:99];
    } @catch (NSException *exception) {
        NSString *detail = [NSString stringWithFormat:@"%@ caught", exception.name];
        [BSPActivityLog record:BSPActivityTypeError detail:detail];
    }
    [self refreshRecentActivity];
}

- (void)showHangConfirm {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Simulate Fatal Hang?"
                         message:@"The main thread will be blocked for 8 seconds. The UI will freeze; the app will not appear to respond until the freeze ends."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hang App"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [self simulateHang];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)simulateHang {
    [BSPActivityLog record:BSPActivityTypeHang detail:@"Main thread frozen"];
    [self refreshRecentActivity];
    // Eight-second freeze — matches the Android/SwiftUI demo copy. With the
    // fatal-only hang detector this won't produce a hang report (main recovers),
    // but the local activity entry above shows the user the event was logged.
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:8.0];
    while ([[NSDate date] compare:until] == NSOrderedAscending) { }
}

- (void)showFeedbackDialog {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Send Feedback"
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Title";
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Description";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Send"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *title = alert.textFields[0].text ?: @"";
        NSString *descText = alert.textFields[1].text ?: @"";
        NSString *description = descText.length > 0 ? descText : nil;
        [strongSelf sendFeedbackWithTitle:title description:description];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)sendFeedbackWithTitle:(NSString *)title description:(NSString *)description {
    self.feedbackStatus = @"Sending...";
    __weak typeof(self) weakSelf = self;
    [[BugSplat shared] postFeedback:title
                        description:description
                           userName:nil
                          userEmail:nil
                             appKey:nil
                        attachments:nil
                         completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error) {
                strongSelf.feedbackStatus = [NSString stringWithFormat:@"Feedback failed: %@",
                                              error.localizedDescription];
            } else {
                strongSelf.feedbackStatus = @"Feedback sent — thank you!";
                NSString *detail = title.length == 0
                    ? @"Feedback submitted"
                    : [NSString stringWithFormat:@"“%@”", title];
                [BSPActivityLog record:BSPActivityTypeFeedback detail:detail];
                [strongSelf refreshRecentActivity];
            }
        });
    }];
}

- (void)openDashboard {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://app.bugsplat.com/v2/dashboard"];
    components.queryItems = @[ [NSURLQueryItem queryItemWithName:@"database" value:[self database]] ];
    NSURL *url = components.URL;
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
