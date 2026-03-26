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

    // Add a "Send Feedback" button that presents a dialog
    NSButton *feedbackButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    feedbackButton.title = @"Send Feedback";
    feedbackButton.bezelStyle = NSBezelStyleRounded;
    feedbackButton.target = self;
    feedbackButton.action = @selector(showFeedbackDialog:);
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

- (IBAction)showFeedbackDialog:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Send Feedback";
    [alert addButtonWithTitle:@"Send"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *titleField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 22)];
    titleField.placeholderString = @"Title";

    NSTextField *descriptionField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 22)];
    descriptionField.placeholderString = @"Description";

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 300, 52)];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    [stack addArrangedSubview:titleField];
    [stack addArrangedSubview:descriptionField];

    alert.accessoryView = stack;
    [alert.window setInitialFirstResponder:titleField];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *title = titleField.stringValue;
        if (title.length == 0) return;
        NSString *description = descriptionField.stringValue.length > 0 ? descriptionField.stringValue : nil;

        [[BugSplat shared] postFeedback:title
                            description:description
                               userName:nil
                              userEmail:nil
                                 appKey:nil
                            attachments:nil
                             completion:^(NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *confirm = [[NSAlert alloc] init];
                confirm.messageText = error ? @"Feedback Failed" : @"Feedback Sent";
                confirm.informativeText = error ? error.localizedDescription : @"Your feedback was submitted successfully!";
                [confirm addButtonWithTitle:@"OK"];
                [confirm runModal];
            });
        }];
    }
}

@end
