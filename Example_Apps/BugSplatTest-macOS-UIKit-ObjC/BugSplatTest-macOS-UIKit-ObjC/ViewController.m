//
//  ViewController.m
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "ViewController.h"
#import "BSPDemoTheme.h"
#import "BSPDemoViews.h"
#import "BSPActivityLog.h"
#import <BugSplat/BugSplat.h>

static NSTimeInterval const kBSPSplatGestureWindowSeconds = 1.2;
static NSInteger const kBSPSplatGestureKeyCount = 8;

@interface ViewController ()
@property (nonatomic, strong) NSStackView *contentStack;
@property (nonatomic, strong) NSStackView *recentActivityList;
@property (nonatomic, strong) NSTextField *recentEmptyLabel;
@property (nonatomic, strong) NSTextField *footerLabel;
@property (nonatomic, strong) id keyDownMonitor;
@property (nonatomic, strong) id keyUpMonitor;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *pressedKeyCodes;
@property (nonatomic, assign) NSTimeInterval splatWindowStart;
@end

@implementation ViewController

#pragma mark - Lifecycle

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 760, 720)];
    root.wantsLayer = YES;
    root.layer.backgroundColor = BSPDemoTheme.screenBg.CGColor;
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.pressedKeyCodes = [NSMutableSet set];
    [self buildLayout];
    [self renderRecentActivity];
    [self installKeyMonitors];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    // Window title set here so it picks up the storyboard's NSWindow after the
    // view is attached.
    self.view.window.title = @"BugSplat • Sample App";
    self.view.window.titleVisibility = NSWindowTitleVisible;
    [self renderRecentActivity];
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    if (self.keyDownMonitor) [NSEvent removeMonitor:self.keyDownMonitor];
    if (self.keyUpMonitor) [NSEvent removeMonitor:self.keyUpMonitor];
    self.keyDownMonitor = nil;
    self.keyUpMonitor = nil;
}

#pragma mark - Layout

- (void)buildLayout {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    // Make the stack hug its content vertically so arranged subviews stay at
    // their intrinsic heights instead of stretching to fill the window.
    [stack setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    [self.view addSubview:stack];
    self.contentStack = stack;

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [stack.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:14],
        // Intentionally no bottom constraint - the stack takes its intrinsic
        // height and sits at the top; the window's screenBg fills below.
    ]];

    [self addArranged:[self buildTopBar] spacingAfter:18];
    [self addArranged:[self buildTitleRow] spacingAfter:6];
    [self addArranged:[self buildSubtitle] spacingAfter:22];
    [self addArranged:[self buildSectionHeader:@"TRIGGER AN EVENT"] spacingAfter:12];
    [self addArranged:[self buildCardGrid] spacingAfter:18];
    [self addArranged:[self buildRecentActivityCard] spacingAfter:18];
    [self addArranged:[self buildFooter] spacingAfter:0];
}

- (void)addArranged:(NSView *)view spacingAfter:(CGFloat)spacing {
    [self.contentStack addArrangedSubview:view];
    [self.contentStack setCustomSpacing:spacing afterView:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:self.contentStack.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:self.contentStack.trailingAnchor],
    ]];
}

- (NSView *)buildTopBar {
    NSView *bar = [[NSView alloc] initWithFrame:NSZeroRect];
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    NSImage *wordmarkImage = [NSImage imageNamed:@"bugsplat_wordmark"];
    NSImageView *wordmark = [NSImageView imageViewWithImage:wordmarkImage ?: [NSImage imageNamed:NSImageNameApplicationIcon]];
    wordmark.imageScaling = NSImageScaleProportionallyUpOrDown;
    wordmark.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:wordmark];

    NSTextField *version = [NSTextField labelWithString:[self sdkVersionString]];
    version.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    version.textColor = BSPDemoTheme.textSecondary;
    version.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:version];

    BSPStatusPill *pill = [[BSPStatusPill alloc] initWithConnected:YES];
    [bar addSubview:pill];

    CGFloat aspect = (wordmarkImage.size.height > 0
                      ? wordmarkImage.size.width / wordmarkImage.size.height
                      : 2.78);
    [NSLayoutConstraint activateConstraints:@[
        [wordmark.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [wordmark.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [wordmark.heightAnchor constraintEqualToConstant:30],
        [wordmark.widthAnchor constraintEqualToAnchor:wordmark.heightAnchor multiplier:aspect],

        [pill.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [pill.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [version.trailingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:-10],
        [version.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [version.leadingAnchor constraintGreaterThanOrEqualToAnchor:wordmark.trailingAnchor constant:10],

        [bar.heightAnchor constraintEqualToConstant:38],
    ]];
    return bar;
}

- (NSView *)buildTitleRow {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = [NSTextField labelWithString:@"BugSplat SDK · Demo"];
    title.font = [NSFont systemFontOfSize:28 weight:NSFontWeightBold];
    title.textColor = BSPDemoTheme.textPrimary;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:title];

    BSPDatabaseBadge *badge = [[BSPDatabaseBadge alloc] initWithText:[self databaseName]];
    [row addSubview:badge];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [title.topAnchor constraintEqualToAnchor:row.topAnchor],
        [title.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],

        [badge.leadingAnchor constraintEqualToAnchor:title.trailingAnchor constant:10],
        [badge.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [badge.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor],
    ]];
    return row;
}

- (NSView *)buildSubtitle {
    NSTextField *label = [NSTextField wrappingLabelWithString:@"Trigger an event. We catch it, group it, route it to your dashboard."];
    label.font = [NSFont systemFontOfSize:14];
    label.textColor = BSPDemoTheme.textSecondary;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.maximumNumberOfLines = 2;
    return label;
}

- (NSView *)buildSectionHeader:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    label.textColor = BSPDemoTheme.textTertiary;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    // Bake in tracking via attributed string for the small-caps look.
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: BSPDemoTheme.textTertiary,
        NSKernAttributeName: @1.4,
    };
    label.attributedStringValue = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    return label;
}

- (NSView *)buildCardGrid {
    BSPEventCardView *crash = [[BSPEventCardView alloc] initWithIconNamed:@"splat_crash"
                                                                    title:@"Crash"
                                                                 subtitle:@"Native crash · stack + threads + memory"
                                                                 shortcut:@"⌘1"];
    crash.target = self;
    crash.action = @selector(triggerCrash:);

    BSPEventCardView *error = [[BSPEventCardView alloc] initWithIconNamed:@"splat_error"
                                                                    title:@"Non-Crash Error"
                                                                 subtitle:@"Exception caught · app keeps running"
                                                                 shortcut:@"⌘2"];
    error.target = self;
    error.action = @selector(triggerNonCrashError:);

    BSPEventCardView *feedback = [[BSPEventCardView alloc] initWithIconNamed:@"splat_feedback"
                                                                       title:@"User Feedback"
                                                                    subtitle:@"Open the feedback sheet"
                                                                    shortcut:@"⌘3"];
    feedback.target = self;
    feedback.action = @selector(triggerFeedback:);

    BSPEventCardView *hang = [[BSPEventCardView alloc] initWithIconNamed:@"splat_hang"
                                                                   title:@"Hang"
                                                                subtitle:@"Freeze main thread for 8 seconds"
                                                                shortcut:@"⌘4"];
    hang.target = self;
    hang.action = @selector(triggerHang:);

    NSStackView *topRow = [NSStackView stackViewWithViews:@[crash, error]];
    topRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    topRow.distribution = NSStackViewDistributionFillEqually;
    topRow.spacing = 14;
    topRow.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *bottomRow = [NSStackView stackViewWithViews:@[feedback, hang]];
    bottomRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bottomRow.distribution = NSStackViewDistributionFillEqually;
    bottomRow.spacing = 14;
    bottomRow.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *grid = [NSStackView stackViewWithViews:@[topRow, bottomRow]];
    grid.orientation = NSUserInterfaceLayoutOrientationVertical;
    grid.distribution = NSStackViewDistributionFillEqually;
    grid.alignment = NSLayoutAttributeLeading;
    grid.spacing = 14;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [topRow.leadingAnchor constraintEqualToAnchor:grid.leadingAnchor],
        [topRow.trailingAnchor constraintEqualToAnchor:grid.trailingAnchor],
        [bottomRow.leadingAnchor constraintEqualToAnchor:grid.leadingAnchor],
        [bottomRow.trailingAnchor constraintEqualToAnchor:grid.trailingAnchor],
    ]];
    return grid;
}

- (NSView *)buildRecentActivityCard {
    BSPRoundedCardView *card = [[BSPRoundedCardView alloc] initWithFrame:NSZeroRect];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *header = [[NSView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:header];

    NSTextField *title = [NSTextField labelWithString:@""];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: BSPDemoTheme.textTertiary,
        NSKernAttributeName: @1.4,
    };
    title.attributedStringValue = [[NSAttributedString alloc] initWithString:@"RECENT ACTIVITY" attributes:attrs];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:title];

    NSButton *link = [NSButton buttonWithTitle:@"View dashboard ↗" target:self action:@selector(openDashboard:)];
    link.bordered = NO;
    NSDictionary *linkAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: BSPDemoTheme.link,
    };
    link.attributedTitle = [[NSAttributedString alloc] initWithString:@"View dashboard ↗" attributes:linkAttrs];
    link.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:link];

    NSStackView *list = [[NSStackView alloc] initWithFrame:NSZeroRect];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.alignment = NSLayoutAttributeLeading;
    list.spacing = 10;
    list.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:list];
    self.recentActivityList = list;

    NSTextField *empty = [NSTextField labelWithString:@"No events yet — tap a card above to get started."];
    empty.font = [NSFont systemFontOfSize:13];
    empty.textColor = BSPDemoTheme.textTertiary;
    empty.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:empty];
    self.recentEmptyLabel = empty;

    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [header.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [header.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],

        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [title.topAnchor constraintEqualToAnchor:header.topAnchor],
        [title.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],

        [link.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [link.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [list.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:14],
        [list.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [list.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],

        [empty.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:14],
        [empty.leadingAnchor constraintEqualToAnchor:list.leadingAnchor],
        [empty.trailingAnchor constraintLessThanOrEqualToAnchor:list.trailingAnchor],

        [card.bottomAnchor constraintGreaterThanOrEqualToAnchor:list.bottomAnchor constant:14],
        [card.bottomAnchor constraintGreaterThanOrEqualToAnchor:empty.bottomAnchor constant:14],
    ]];
    return card;
}

- (NSView *)buildFooter {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.alignment = NSTextAlignmentCenter;

    NSMutableAttributedString *str = [[NSMutableAttributedString alloc] init];

    NSFont *bodyFont = [NSFont systemFontOfSize:13];
    NSFont *boldFont = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];

    // Pick the closest macOS handwriting font without requiring a bundled file.
    NSFont *handwriting = [NSFont fontWithName:@"Bradley Hand" size:16]
                       ?: [NSFont fontWithName:@"BradleyHandITCTT-Bold" size:16]
                       ?: [NSFont fontWithName:@"Noteworthy" size:16]
                       ?: [NSFont fontWithName:@"Marker Felt" size:16]
                       ?: [NSFont fontWithDescriptor:[[NSFont systemFontOfSize:14] fontDescriptor]
                                  size:14];

    [str appendAttributedString:[[NSAttributedString alloc] initWithString:@"Press "
                                                                attributes:@{NSFontAttributeName: bodyFont,
                                                                             NSForegroundColorAttributeName: BSPDemoTheme.textTertiary}]];
    [str appendAttributedString:[[NSAttributedString alloc] initWithString:@"any 8 keys at once"
                                                                attributes:@{NSFontAttributeName: boldFont,
                                                                             NSForegroundColorAttributeName: BSPDemoTheme.textSecondary}]];
    [str appendAttributedString:[[NSAttributedString alloc] initWithString:@" to send feedback — "
                                                                attributes:@{NSFontAttributeName: bodyFont,
                                                                             NSForegroundColorAttributeName: BSPDemoTheme.textTertiary}]];
    [str appendAttributedString:[[NSAttributedString alloc] initWithString:@"splat your keyboard."
                                                                attributes:@{NSFontAttributeName: handwriting,
                                                                             NSForegroundColorAttributeName: BSPDemoTheme.link}]];

    label.attributedStringValue = str;
    self.footerLabel = label;
    return label;
}

#pragma mark - Recent activity rendering

- (void)renderRecentActivity {
    for (NSView *sub in [self.recentActivityList.arrangedSubviews copy]) {
        [self.recentActivityList removeArrangedSubview:sub];
        [sub removeFromSuperview];
    }

    NSArray<NSDictionary *> *entries = [BSPActivityLog all];
    if (entries.count == 0) {
        self.recentEmptyLabel.hidden = NO;
        self.recentActivityList.hidden = YES;
        return;
    }

    self.recentEmptyLabel.hidden = YES;
    self.recentActivityList.hidden = NO;

    for (NSDictionary *entry in entries) {
        NSString *type = entry[BSPActivityEntryKeyType] ?: @"";
        NSString *detail = entry[BSPActivityEntryKeyDetail] ?: @"";
        NSTimeInterval ts = [entry[BSPActivityEntryKeyTimestamp] doubleValue];
        NSString *rel = [BSPActivityLog relativeTimeStringFromSeconds:ts];

        BSPRecentActivityRow *row = [[BSPRecentActivityRow alloc] initWithType:type detail:detail relativeTime:rel];
        [self.recentActivityList addArrangedSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.recentActivityList.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:self.recentActivityList.trailingAnchor],
        ]];
    }
}

#pragma mark - Actions

- (void)triggerCrash:(id)sender {
    [BSPActivityLog record:BSPActivityTypeCrash detail:@"Native crash triggered"];
    [self renderRecentActivity];
    // Null pointer dereference - guaranteed SIGSEGV. Sending an ObjC message
    // to nil silently returns 0, so a plain C deref is what actually crashes.
    volatile int *ptr = NULL;
    *ptr = 42;
}

- (void)triggerNonCrashError:(id)sender {
    NSString *caughtName = @"NSException";
    @try {
        NSArray *empty = @[];
        (void)empty[99];
    } @catch (NSException *e) {
        caughtName = e.name ?: @"NSException";
    }
    [BSPActivityLog record:BSPActivityTypeError
                    detail:[NSString stringWithFormat:@"%@ caught", caughtName]];
    [self renderRecentActivity];
}

- (void)triggerFeedback:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Send Feedback";
    [alert addButtonWithTitle:@"Send"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *titleField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 22)];
    titleField.placeholderString = @"Title";
    NSTextField *descField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 22)];
    descField.placeholderString = @"Description (optional)";

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 320, 52)];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    [stack addArrangedSubview:titleField];
    [stack addArrangedSubview:descField];
    alert.accessoryView = stack;
    [alert.window setInitialFirstResponder:titleField];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *title = titleField.stringValue;
    NSString *desc = descField.stringValue.length > 0 ? descField.stringValue : nil;

    [[BugSplat shared] postFeedback:title.length > 0 ? title : @"(no title)"
                        description:desc
                           userName:nil
                          userEmail:nil
                             appKey:nil
                        attachments:nil
                         completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error) {
                NSString *detail = title.length > 0
                    ? [NSString stringWithFormat:@"“%@”", title]
                    : @"Feedback submitted";
                [BSPActivityLog record:BSPActivityTypeFeedback detail:detail];
                [self renderRecentActivity];
            }
        });
    }];
}

- (void)triggerHang:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Freeze main thread for 8 seconds?";
    alert.informativeText = @"The UI will become unresponsive. The app will recover automatically after 8 seconds.";
    [alert addButtonWithTitle:@"Freeze"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    [BSPActivityLog record:BSPActivityTypeHang detail:@"Main thread frozen"];
    [self renderRecentActivity];

    // Eight-second freeze. Recovers; with the fatal-only hang detector no
    // report is uploaded but the local entry above documents the event.
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:8.0];
    while ([[NSDate date] compare:until] == NSOrderedAscending) { }
}

- (void)openDashboard:(id)sender {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://app.bugsplat.com/v2/dashboard"];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"database" value:[self databaseName]]];
    [[NSWorkspace sharedWorkspace] openURL:components.URL];
}

#pragma mark - Keyboard

- (void)installKeyMonitors {
    __weak typeof(self) weakSelf = self;
    self.keyDownMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        typeof(self) self = weakSelf;
        if (!self) return event;

        // Cmd+1..4 routes to the corresponding card action.
        if ((event.modifierFlags & NSEventModifierFlagCommand) && !event.isARepeat) {
            NSString *chars = event.charactersIgnoringModifiers;
            if (chars.length == 1) {
                unichar c = [chars characterAtIndex:0];
                if (c == '1') { [self triggerCrash:nil]; return nil; }
                if (c == '2') { [self triggerNonCrashError:nil]; return nil; }
                if (c == '3') { [self triggerFeedback:nil]; return nil; }
                if (c == '4') { [self triggerHang:nil]; return nil; }
            }
        }

        if (event.isARepeat) return event;
        [self trackKeyDown:event.keyCode];
        return event;
    }];

    self.keyUpMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyUp
                                                              handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        [weakSelf.pressedKeyCodes removeObject:@(event.keyCode)];
        return event;
    }];
}

- (void)trackKeyDown:(unsigned short)keyCode {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.splatWindowStart > kBSPSplatGestureWindowSeconds) {
        // Window expired; start a fresh one.
        [self.pressedKeyCodes removeAllObjects];
        self.splatWindowStart = now;
    }
    [self.pressedKeyCodes addObject:@(keyCode)];

    if ((NSInteger)self.pressedKeyCodes.count >= kBSPSplatGestureKeyCount) {
        [self.pressedKeyCodes removeAllObjects];
        self.splatWindowStart = 0;
        [self triggerFeedback:nil];
    }
}

#pragma mark - Helpers

- (NSString *)databaseName {
    NSString *db = [[BugSplat shared] bugSplatDatabase];
    return db.length > 0 ? db : @"—";
}

- (NSString *)sdkVersionString {
    NSBundle *bundle = [NSBundle bundleForClass:[BugSplat class]];
    NSString *v = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [NSString stringWithFormat:@"v%@", v.length > 0 ? v : @"—"];
}

@end
