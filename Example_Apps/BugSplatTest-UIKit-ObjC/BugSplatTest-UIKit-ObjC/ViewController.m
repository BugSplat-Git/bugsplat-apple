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

    // Add a "Send Feedback" button that presents a dialog
    UIButton *feedbackButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [feedbackButton setTitle:@"Send Feedback" forState:UIControlStateNormal];
    [feedbackButton addTarget:self action:@selector(showFeedbackDialog) forControlEvents:UIControlEventTouchUpInside];
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

- (void)showFeedbackDialog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Send Feedback" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Title";
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Description";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Send" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *title = alert.textFields[0].text;
        if (title.length == 0) return;
        NSString *description = alert.textFields[1].text.length > 0 ? alert.textFields[1].text : nil;

        [[BugSplat shared] postFeedback:title
                            description:description
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
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
