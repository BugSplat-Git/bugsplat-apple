//
//  ViewController.m
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "ViewController.h"
#import <BugSplatMac/BugSplatMac.h>

@interface ViewController ()
@property (nonatomic, strong) NSTextField *titleField;
@property (nonatomic, strong) NSTextField *descriptionField;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    // Attributes can be set any time and can contain dynamic values
    // Attributes set in this app session will only appear if the app session in which they are set terminates with an app crash
    [[BugSplat shared] setValue:[[NSDate now] description] forAttribute:@"DateAndTime"];

    // Add feedback input fields and button programmatically
    self.titleField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.titleField.placeholderString = @"Feedback title";

    self.descriptionField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.descriptionField.placeholderString = @"Description";

    NSButton *feedbackButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    feedbackButton.title = @"Send Feedback";
    feedbackButton.bezelStyle = NSBezelStyleRounded;
    feedbackButton.target = self;
    feedbackButton.action = @selector(sendFeedback:);

    NSStackView *stack = [NSStackView stackViewWithViews:@[self.titleField, self.descriptionField, feedbackButton]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:30],
        [self.titleField.widthAnchor constraintEqualToConstant:280],
    ]];
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

- (IBAction)crashApp:(id)sender {
    NSLog(@"crashApp called from touch!");
    assert(NO);
}

- (IBAction)sendFeedback:(id)sender {
    NSString *title = self.titleField.stringValue;
    if (title.length == 0) return;
    NSString *description = self.descriptionField.stringValue.length > 0 ? self.descriptionField.stringValue : nil;

    [[BugSplat shared] postFeedback:title
                        description:description
                           userName:nil
                          userEmail:nil
                             appKey:nil
                        attachments:nil
                         completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"Feedback failed: %@", error.localizedDescription);
            } else {
                NSLog(@"Feedback submitted successfully!");
                self.titleField.stringValue = @"";
                self.descriptionField.stringValue = @"";
            }
        });
    }];
}

@end
