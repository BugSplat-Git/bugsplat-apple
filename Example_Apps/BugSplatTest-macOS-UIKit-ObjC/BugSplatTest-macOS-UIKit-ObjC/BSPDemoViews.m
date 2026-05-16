//
//  BSPDemoViews.m
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BSPDemoViews.h"
#import "BSPDemoTheme.h"
#import "BSPActivityLog.h"

#pragma mark - BSPRoundedCardView

@implementation BSPRoundedCardView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _cornerRadius = 14;
        self.wantsLayer = YES;
        [self refreshLayer];
    }
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    [self refreshLayer];
}

- (void)refreshLayer {
    self.layer.cornerRadius = _cornerRadius;
    self.layer.backgroundColor = BSPDemoTheme.cardBg.CGColor;
    self.layer.borderColor = BSPDemoTheme.cardStroke.CGColor;
    self.layer.borderWidth = 1;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self refreshLayer];
}

@end


#pragma mark - BSPStatusPill

@implementation BSPStatusPill {
    BOOL _connected;
}

- (instancetype)initWithConnected:(BOOL)connected {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _connected = connected;
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self build];
    }
    return self;
}

- (void)build {
    self.layer.backgroundColor = NSColor.whiteColor.CGColor;
    self.layer.borderColor = BSPDemoTheme.pillStroke.CGColor;
    self.layer.borderWidth = 1;
    self.layer.cornerRadius = 11;

    NSView *dot = [[NSView alloc] initWithFrame:NSZeroRect];
    dot.wantsLayer = YES;
    dot.layer.backgroundColor = BSPDemoTheme.connectedDot.CGColor;
    dot.layer.cornerRadius = 4;
    dot.layer.opacity = _connected ? 1.0 : 0.35;
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:dot];

    NSTextField *label = [NSTextField labelWithString:_connected ? @"Connected" : @"Offline"];
    label.font = [NSFont systemFontOfSize:12];
    label.textColor = BSPDemoTheme.textPrimary;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [dot.widthAnchor constraintEqualToConstant:8],
        [dot.heightAnchor constraintEqualToConstant:8],
        [dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [dot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:6],
        [label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.heightAnchor constraintEqualToConstant:22],
    ]];
}

@end


#pragma mark - BSPDatabaseBadge

@implementation BSPDatabaseBadge

- (instancetype)initWithText:(NSString *)text {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = BSPDemoTheme.badgeBg.CGColor;
        self.layer.cornerRadius = 8;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        NSTextField *label = [NSTextField labelWithString:text];
        label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        label.textColor = BSPDemoTheme.textSecondary;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [label.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
            [label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3],
        ]];
    }
    return self;
}

@end


#pragma mark - BSPShortcutChip

@implementation BSPShortcutChip

- (instancetype)initWithText:(NSString *)text {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = BSPDemoTheme.badgeBg.CGColor;
        self.layer.cornerRadius = 6;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        NSTextField *label = [NSTextField labelWithString:text];
        label.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        label.textColor = BSPDemoTheme.textTertiary;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
            [label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [label.topAnchor constraintEqualToAnchor:self.topAnchor constant:2],
            [label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2],
        ]];
    }
    return self;
}

@end


#pragma mark - BSPEventCardView

@interface BSPEventCardView ()
@property (nonatomic, strong) NSTrackingArea *tracking;
@property (nonatomic, assign) BOOL hovering;
@end

@implementation BSPEventCardView

- (instancetype)initWithIconNamed:(NSString *)imageName
                            title:(NSString *)title
                         subtitle:(NSString *)subtitle
                         shortcut:(NSString *)shortcut {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        [self applyAppearance];

        NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageNamed:imageName] ?: [NSImage imageNamed:NSImageNameApplicationIcon]];
        icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:icon];

        NSTextField *titleLabel = [NSTextField labelWithString:title];
        titleLabel.font = [NSFont systemFontOfSize:15 weight:NSFontWeightBold];
        titleLabel.textColor = BSPDemoTheme.textPrimary;
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:titleLabel];

        NSTextField *subtitleLabel = [NSTextField labelWithString:subtitle];
        subtitleLabel.font = [NSFont systemFontOfSize:13];
        subtitleLabel.textColor = BSPDemoTheme.textSecondary;
        subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:subtitleLabel];

        NSLayoutConstraint *titleTrailing;
        if (shortcut.length > 0) {
            BSPShortcutChip *chip = [[BSPShortcutChip alloc] initWithText:shortcut];
            [self addSubview:chip];
            [NSLayoutConstraint activateConstraints:@[
                [chip.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
                [chip.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            ]];
            titleTrailing = [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:chip.leadingAnchor constant:-10];
        } else {
            titleTrailing = [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16];
        }

        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:48],
            [icon.heightAnchor constraintEqualToConstant:48],

            [titleLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],
            [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:18],
            titleTrailing,

            [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
            [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2],
            [subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],
            [subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-18],

            [self.heightAnchor constraintGreaterThanOrEqualToConstant:84],
        ]];
    }
    return self;
}

- (void)applyAppearance {
    self.layer.cornerRadius = 14;
    self.layer.borderColor = BSPDemoTheme.cardStroke.CGColor;
    self.layer.borderWidth = 1;
    self.layer.backgroundColor = (_hovering
                                  ? [BSPDemoTheme.cardBg blendedColorWithFraction:0.04 ofColor:[NSColor blackColor]].CGColor
                                  : BSPDemoTheme.cardBg.CGColor);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.tracking) [self removeTrackingArea:self.tracking];
    self.tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                  options:(NSTrackingMouseEnteredAndExited |
                                                           NSTrackingActiveInActiveApp |
                                                           NSTrackingInVisibleRect)
                                                    owner:self
                                                 userInfo:nil];
    [self addTrackingArea:self.tracking];
}

- (void)mouseEntered:(NSEvent *)event {
    self.hovering = YES;
    [[NSCursor pointingHandCursor] push];
    [self applyAppearance];
}

- (void)mouseExited:(NSEvent *)event {
    self.hovering = NO;
    [NSCursor pop];
    [self applyAppearance];
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, self.bounds)) {
        [self sendAction:self.action to:self.target];
    }
}

@end


#pragma mark - BSPRecentActivityRow

@implementation BSPRecentActivityRow

- (instancetype)initWithType:(NSString *)type
                       detail:(NSString *)detail
                  relativeTime:(NSString *)relativeTime {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        NSColor *dotColor = BSPDemoTheme.activityError;
        NSString *labelText = @"Error";
        if ([type isEqualToString:BSPActivityTypeCrash]) {
            dotColor = BSPDemoTheme.activityCrash;
            labelText = @"Crash";
        } else if ([type isEqualToString:BSPActivityTypeError]) {
            dotColor = BSPDemoTheme.activityError;
            labelText = @"Error";
        } else if ([type isEqualToString:BSPActivityTypeFeedback]) {
            dotColor = BSPDemoTheme.activityFeedback;
            labelText = @"Feedback";
        } else if ([type isEqualToString:BSPActivityTypeHang]) {
            dotColor = BSPDemoTheme.activityHang;
            labelText = @"Hang";
        }

        NSView *dot = [[NSView alloc] initWithFrame:NSZeroRect];
        dot.wantsLayer = YES;
        dot.layer.backgroundColor = dotColor.CGColor;
        dot.layer.cornerRadius = 4;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:dot];

        NSTextField *label = [NSTextField labelWithString:labelText];
        label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightBold];
        label.textColor = BSPDemoTheme.textPrimary;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:label];

        NSTextField *detailLabel = [NSTextField labelWithString:detail];
        detailLabel.font = [NSFont systemFontOfSize:13];
        detailLabel.textColor = BSPDemoTheme.textSecondary;
        detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:detailLabel];

        NSTextField *timeLabel = [NSTextField labelWithString:relativeTime];
        timeLabel.font = [NSFont systemFontOfSize:12];
        timeLabel.textColor = BSPDemoTheme.textTertiary;
        timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:timeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [dot.widthAnchor constraintEqualToConstant:8],
            [dot.heightAnchor constraintEqualToConstant:8],
            [dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [dot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:12],
            [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [label.widthAnchor constraintEqualToConstant:74],

            [detailLabel.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:6],
            [detailLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [timeLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:detailLabel.trailingAnchor constant:10],
            [timeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [timeLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [self.heightAnchor constraintGreaterThanOrEqualToConstant:24],
        ]];
    }
    return self;
}

@end
