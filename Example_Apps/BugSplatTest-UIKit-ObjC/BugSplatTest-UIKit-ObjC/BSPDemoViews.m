//
//  BSPDemoViews.m
//  BugSplatTest-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "BSPDemoViews.h"
#import "BSPDemoTheme.h"
#import "BSPActivityLog.h"

#pragma mark - BSPStatusPill

@implementation BSPStatusPill

- (instancetype)initWithConnected:(BOOL)connected {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    self.backgroundColor = [UIColor whiteColor];
    self.layer.borderColor = BSPDemoTheme.pillStroke.CGColor;
    self.layer.borderWidth = 1.0;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *dot = [[UIView alloc] init];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.backgroundColor = BSPDemoTheme.connectedDot;
    dot.alpha = connected ? 1.0 : 0.35;
    dot.layer.cornerRadius = 4;
    [self addSubview:dot];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = connected ? @"Connected" : @"Offline";
    label.font = [UIFont systemFontOfSize:12];
    label.textColor = BSPDemoTheme.textPrimary;
    [self addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [dot.widthAnchor constraintEqualToConstant:8],
        [dot.heightAnchor constraintEqualToConstant:8],
        [dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [dot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:6],
        [label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [label.topAnchor constraintEqualToAnchor:self.topAnchor constant:5],
        [label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-5],
    ]];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Capsule shape: half-height corner radius.
    self.layer.cornerRadius = self.bounds.size.height / 2.0;
}

@end

#pragma mark - BSPDatabaseBadge

@interface BSPDatabaseBadge ()
@property (nonatomic, strong) UILabel *label;
@end

@implementation BSPDatabaseBadge

- (instancetype)initWithText:(NSString *)text {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = BSPDemoTheme.badgeBg;
    self.layer.cornerRadius = 8;

    self.label = [[UILabel alloc] init];
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    self.label.text = text;
    self.label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.label.textColor = BSPDemoTheme.textSecondary;
    [self addSubview:self.label];

    [NSLayoutConstraint activateConstraints:@[
        [self.label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [self.label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [self.label.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [self.label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
    ]];

    return self;
}

- (void)setText:(NSString *)text {
    self.label.text = text;
}

@end

#pragma mark - BSPEventCardView

@implementation BSPEventCardView

- (instancetype)initWithIconName:(NSString *)iconName
                           title:(NSString *)title
                        subtitle:(NSString *)subtitle {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = BSPDemoTheme.cardBg;
    self.layer.cornerRadius = 14;
    self.layer.borderColor = BSPDemoTheme.cardStroke.CGColor;
    self.layer.borderWidth = 1;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:iconName]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.userInteractionEnabled = NO;
    [self addSubview:icon];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor = BSPDemoTheme.textPrimary;
    titleLabel.userInteractionEnabled = NO;
    [self addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = subtitle;
    subtitleLabel.font = [UIFont systemFontOfSize:14];
    subtitleLabel.textColor = BSPDemoTheme.textSecondary;
    subtitleLabel.numberOfLines = 0;
    subtitleLabel.userInteractionEnabled = NO;
    [self addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:52],
        [icon.heightAnchor constraintEqualToConstant:52],

        [titleLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:16],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2],
        [subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-16],

        [self.heightAnchor constraintGreaterThanOrEqualToConstant:84],
    ]];

    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1.0;
}

@end

#pragma mark - BSPRecentActivityRow

@implementation BSPRecentActivityRow

- (instancetype)initWithType:(NSString *)type
                      detail:(NSString *)detail
                   timestamp:(NSTimeInterval)timestamp {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    self.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *dot = [[UIView alloc] init];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.backgroundColor = [self dotColorForType:type];
    dot.layer.cornerRadius = 4;
    [self addSubview:dot];

    UILabel *typeLabel = [[UILabel alloc] init];
    typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    typeLabel.text = [self labelForType:type];
    typeLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    typeLabel.textColor = BSPDemoTheme.textPrimary;
    [typeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [typeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self addSubview:typeLabel];

    UILabel *detailLabel = [[UILabel alloc] init];
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    detailLabel.text = detail;
    detailLabel.font = [UIFont systemFontOfSize:14];
    detailLabel.textColor = BSPDemoTheme.textSecondary;
    detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    detailLabel.numberOfLines = 1;
    [detailLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [detailLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self addSubview:detailLabel];

    UILabel *timeLabel = [[UILabel alloc] init];
    timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    timeLabel.text = [BSPActivityLog relativeTimeStringFromSeconds:timestamp];
    timeLabel.font = [UIFont systemFontOfSize:13];
    timeLabel.textColor = BSPDemoTheme.textTertiary;
    timeLabel.textAlignment = NSTextAlignmentRight;
    [timeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self addSubview:timeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [dot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [dot.widthAnchor constraintEqualToConstant:8],
        [dot.heightAnchor constraintEqualToConstant:8],

        [typeLabel.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:12],
        [typeLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [detailLabel.leadingAnchor constraintEqualToAnchor:typeLabel.trailingAnchor constant:14],
        [detailLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:timeLabel.leadingAnchor constant:-10],

        [timeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [timeLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [self.heightAnchor constraintGreaterThanOrEqualToConstant:20],
        [self.topAnchor constraintEqualToAnchor:typeLabel.topAnchor constant:-2],
        [self.bottomAnchor constraintEqualToAnchor:typeLabel.bottomAnchor constant:2],
    ]];

    return self;
}

- (UIColor *)dotColorForType:(NSString *)type {
    if ([type isEqualToString:BSPActivityTypeCrash])    return BSPDemoTheme.activityCrash;
    if ([type isEqualToString:BSPActivityTypeError])    return BSPDemoTheme.activityError;
    if ([type isEqualToString:BSPActivityTypeFeedback]) return BSPDemoTheme.activityFeedback;
    if ([type isEqualToString:BSPActivityTypeHang])     return BSPDemoTheme.activityHang;
    return BSPDemoTheme.textTertiary;
}

- (NSString *)labelForType:(NSString *)type {
    if ([type isEqualToString:BSPActivityTypeCrash])    return @"Crash";
    if ([type isEqualToString:BSPActivityTypeError])    return @"Error";
    if ([type isEqualToString:BSPActivityTypeFeedback]) return @"Feedback";
    if ([type isEqualToString:BSPActivityTypeHang])     return @"Hang";
    return type;
}

@end
