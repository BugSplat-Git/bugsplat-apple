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
    [[BugSplat shared] setValue:[[NSDate now] description] forAttribute:@"ViewController viewDidLoad: Date+Time"];
}

- (IBAction)crashApp:(id)sender {
    NSNumber *number = [self.array objectAtIndex:2];
    NSLog(@"number = %ld", [number longValue]);
}


@end
