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

    // Add a "Simulate Hang" button for demoing fatal-hang detection.
    UIButton *hangButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [hangButton setTitle:@"Simulate Hang" forState:UIControlStateNormal];
    [hangButton addTarget:self action:@selector(simulateHang) forControlEvents:UIControlEventTouchUpInside];
    hangButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hangButton];
    [NSLayoutConstraint activateConstraints:@[
        [hangButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [hangButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:100]
    ]];
}

- (IBAction)crashApp:(id)sender {
    NSNumber *number = [self.array objectAtIndex:2];
    NSLog(@"number = %ld", [number longValue]);
}

- (void)simulateHang {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Simulate Fatal Hang?"
                         message:@"The main thread will be blocked indefinitely. The UI will freeze and the only way to recover is to force-quit the app (swipe up from the app switcher). On the next launch, a fatal-hang report will be uploaded. Continue?"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hang App" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        // Blocks the main thread forever so the only way to exit is to force-quit the
        // app. That produces a fatal-hang report that is uploaded on the next launch.
        // If the main thread were allowed to recover, the persisted report would be
        // discarded because non-fatal hangs are intentionally not reported.
        NSLog(@"BugSplat sample: Simulating main-thread hang. Force-quit to see a fatal-hang report on the next launch.");
        while (1) { }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
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
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *message = error ? [NSString stringWithFormat:@"Failed: %@", error.localizedDescription] : @"Feedback submitted successfully!";
                UIAlertController *confirm = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
                [confirm addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:confirm animated:YES completion:nil];
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
