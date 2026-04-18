//
//  ViewController.m
//  BugSplatTest-macOS-UIKit-ObjC
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#import "ViewController.h"
#import <BugSplat/BugSplat.h>

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

    // Add a "Simulate Hang" button for demoing fatal-hang detection.
    NSButton *hangButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    hangButton.title = @"Simulate Hang";
    hangButton.bezelStyle = NSBezelStyleRounded;
    hangButton.target = self;
    hangButton.action = @selector(simulateHang:);
    hangButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hangButton];
    [NSLayoutConstraint activateConstraints:@[
        [hangButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [hangButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:80]
    ]];
}

- (IBAction)simulateHang:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Simulate Fatal Hang?";
    alert.informativeText = @"The main thread will be blocked indefinitely. The UI will freeze and the only way to recover is to force-quit the app (Cmd+Option+Esc, then Force Quit) or kill the process from a terminal (`killall -9 BugSplatTest-macOS-UIKit-ObjC`). On the next launch, a fatal-hang report will be uploaded. Continue?";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Hang App"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    // Blocks the main thread forever so the only way to exit is to force-quit the
    // app. That produces a fatal-hang report that is uploaded on the next launch.
    // If the main thread were allowed to recover, the persisted report would be
    // discarded because non-fatal hangs are intentionally not reported.
    NSLog(@"BugSplat sample: Simulating main-thread hang. Force-quit to see a fatal-hang report on the next launch.");
    while (1) { }
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
