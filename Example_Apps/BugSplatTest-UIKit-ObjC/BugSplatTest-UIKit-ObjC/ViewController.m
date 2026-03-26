//
//  ViewController.m
//  BugSplatTest-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "ViewController.h"
#import <BugSplat/BugSplat.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.array = @[@1, @2];

    // Attributes can be set any time and can contain dynamic values
    // Attributes set in this app session will only appear if the app session in which they are set terminates with an app crash
    [[BugSplat shared] setValue:[[NSDate now] description] forAttribute:@"ViewDidLoadDateTime"];

    // Add a "Send Feedback" button programmatically
    UIButton *feedbackButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [feedbackButton setTitle:@"Send Feedback" forState:UIControlStateNormal];
    [feedbackButton addTarget:self action:@selector(sendFeedback) forControlEvents:UIControlEventTouchUpInside];
    feedbackButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:feedbackButton];
    [NSLayoutConstraint activateConstraints:@[
        [feedbackButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [feedbackButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:60]
    ]];
}

- (IBAction)crashApp:(id)sender {
    NSNumber *number = [self.array objectAtIndex:2];
    NSLog(@"number = %ld", [number longValue]);
}

- (void)sendFeedback {
    [[BugSplat shared] postFeedback:@"User Feedback"
                        description:@"This is a test feedback submission from the UIKit ObjC example app."
                           userName:nil
                          userEmail:nil
                             appKey:nil
                        attachments:nil
                         completion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Feedback failed: %@", error.localizedDescription);
        } else {
            NSLog(@"Feedback submitted successfully!");
        }
    }];
}

@end
