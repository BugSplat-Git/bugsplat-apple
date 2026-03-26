//
//  ViewController.m
//  BugSplatTest-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "ViewController.h"
#import <BugSplat/BugSplat.h>

@interface ViewController ()
@property (nonatomic, strong) UITextField *titleField;
@property (nonatomic, strong) UITextField *descriptionField;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.array = @[@1, @2];

    // Attributes can be set any time and can contain dynamic values
    // Attributes set in this app session will only appear if the app session in which they are set terminates with an app crash
    [[BugSplat shared] setValue:[[NSDate now] description] forAttribute:@"ViewDidLoadDateTime"];

    // Add feedback input fields and button programmatically
    self.titleField = [[UITextField alloc] init];
    self.titleField.placeholder = @"Feedback title";
    self.titleField.borderStyle = UITextBorderStyleRoundedRect;

    self.descriptionField = [[UITextField alloc] init];
    self.descriptionField.placeholder = @"Description";
    self.descriptionField.borderStyle = UITextBorderStyleRoundedRect;

    UIButton *feedbackButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [feedbackButton setTitle:@"Send Feedback" forState:UIControlStateNormal];
    [feedbackButton addTarget:self action:@selector(sendFeedback) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleField, self.descriptionField, feedbackButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:40],
        [self.titleField.widthAnchor constraintEqualToConstant:280],
    ]];
}

- (IBAction)crashApp:(id)sender {
    NSNumber *number = [self.array objectAtIndex:2];
    NSLog(@"number = %ld", [number longValue]);
}

- (void)sendFeedback {
    NSString *title = self.titleField.text;
    if (title.length == 0) return;
    NSString *description = self.descriptionField.text.length > 0 ? self.descriptionField.text : nil;

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
                self.titleField.text = @"";
                self.descriptionField.text = @"";
            }
        });
    }];
}

@end
