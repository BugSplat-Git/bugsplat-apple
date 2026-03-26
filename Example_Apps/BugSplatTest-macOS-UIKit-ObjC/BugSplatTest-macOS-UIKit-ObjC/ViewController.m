//
//  ViewController.m
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "ViewController.h"
#import <BugSplatMac/BugSplatMac.h>

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    // Attributes can be set any time and can contain dynamic values
    // Attributes set in this app session will only appear if the app session in which they are set terminates with an app crash
    [[BugSplat shared] setValue:[[NSDate now] description] forAttribute:@"DateAndTime"];

    // Add a "Send Feedback" button programmatically
    NSButton *feedbackButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    feedbackButton.title = @"Send Feedback";
    feedbackButton.bezelStyle = NSBezelStyleRounded;
    feedbackButton.target = self;
    feedbackButton.action = @selector(sendFeedback:);
    feedbackButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:feedbackButton];
    [NSLayoutConstraint activateConstraints:@[
        [feedbackButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [feedbackButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:40]
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
    [[BugSplat shared] postFeedback:@"User Feedback"
                        description:@"This is a test feedback submission from the macOS ObjC example app."
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
