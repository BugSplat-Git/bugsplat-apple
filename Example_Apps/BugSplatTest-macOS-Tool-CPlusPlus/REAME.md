## Introduction 

BugSplat.xcframework enables posting crash reports from iOS, macOS, and Mac Catalyst applications to BugSplat. Yet another type of macOS application exists: a command line tool or application. This README will cover this type of 'application' and the details of how to configure a command line application to use BugSplat. In addition to detailing how to integrate BugSplat.xcframework into your command line application, this README and example app BugSplatTest-macOS-Tool-CPlusPlus will also discuss integrating with C++.

## Topics Covered

+ Integrating BugSplat.xcframework into C++ Applications
+ Integrating BugSplat.xcframework into Command Line Applications
+ Xcode Build Settings required
+ Linking framework(s)


### Integrating BugSplat.xcframework into C++ Applications

Xcode IDE supports several development languages: Swift, Objective-C, C and C++. What may not be known is that Xcode was modified many years ago to support a 'hybrid' environment called Objective-C++. When the compiler sees a .swift file, it expects to parse and process Swift. Likewise a .m file denotes Objective-C and of course .c denotes C and .cpp denotes C++. The compiler would fail if C++ were written in a .swift file or even a .m file. But how does one use an xcframework that offers a Swift or Objective-C API? This is where Objective-C++ comes in. The file type is .mm and it provides a special environment where both C, C++ and Objective-C can coexist. 

In the Example App BugSplatTest-macOS-Tool-CPlusPlus, BugSplatInit.mm contains both C/C++ and Objective-C. For a C++ app to integrate BugSplat.xcframework, some Objective-C code needs to be written to setup BugSplat within a proper Objective-C environment. Add Objective-C code within the @autoreleasepool { ... } curly brackets. This allows Objective-C's ARC to propertly handle memory and releasing it when it is done.

#### BugSplatInit.mm - code snippet

```objc
#include "BugSplatInit.hpp"

#import <AppKit/AppKit.h> // for NSApplicationDidFinishLaunchingNotification
#import <BugSplatMac/BugSplatMac.h>

@interface MyBugSplatDelegate : NSObject <BugSplatDelegate>
@end

// Call the C++ function that uses Objective-C
int bugSplatInit(const char * bugSplatDatabase)
{
    @autoreleasepool {

        // Initialize BugSplat
        MyBugSplatDelegate *delegate = [[MyBugSplatDelegate alloc] init];

        // Set a BugSplatDelegate
        [[BugSplat shared] setDelegate:delegate];

        // Command Line Tools do not have a GUI. setAutoSubmitCrashReport: YES
        [[BugSplat shared] setAutoSubmitCrashReport:YES];

        NSString *databaseName = [NSString stringWithCString:bugSplatDatabase encoding:NSUTF8StringEncoding];
        NSLog(@"bugSplatInit called with database name: %@", databaseName);

        // Set the BugSplatDatabase name before calling start
        [[BugSplat shared] setBugSplatDatabase:databaseName];

        // Don't forget to call start after you've finished configuring BugSplat
        [[BugSplat shared] start];

        // BugSplat expects a NSApplicationDidFinishLaunchingNotification to be sent before it will process crash reports.
        // In a command line tool without a normal app launch, send the notification manually. This should be sent after [[BugSplat shared] start]
        [[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationDidFinishLaunchingNotification object:nil userInfo:[NSDictionary new]];
    }

    return 0;
}

```

### Integrating BugSplat.xcframework into Command Line Applications

A command line application can be written in several different languages. BugSplatTest-macOS-Tool-CPlusPlus example illustrates a command line application written in C++. Regardless of what language the command line application is written in, there are a few things that are requirements for successfully integrating BugSplat.xcframework and posting crash reports. These techniques are used in the example app BugSplatTest-macOS-Tool-CPlusPlus. These requirements are additional/modifications to requirements already imposed by a GUI based app. For example, it is still a requirement to use symbol-upload-macos as part of a Build Phase Script. That requirement does not change. Neither does having an app database name. This section highlights key differences from the GUI app requirements.

#### BugSplat expectations regardless of the type of application built:
+ BugSplat needs a database name to post crash reports to
+ BugSplat expects an Info.plist
+ BugSplat expects several values within the Info.plist: 
1. set Product Bundle Identifier
2. set Product Name
3. set Current Project Version
4. set Marketing Version (optional)

+ BugSplat expects an AppKit NSApplicationDidFinishLaunchingNotification NSNotication to be posted when the application has completed the startup phase. In this example, it is programmatically sent after [[BugSplat shaerd] start] is called. This NSNotification allows BugSplat to begin processing any crash reports that may have been captured during a prior application session. This would normally be sent by AppKit or UIKit as part of the normal application life cycle, but it is not sent in a command line application.


### Xcode Build Settings required for a Command Line application

BugSplat requires a few Xcode configuration steps to integrate the xcframework with your BugSplat account.
Unlike a normal GUI application, it is not obvious how to set the Info.plist file and key/value pairs that BugSplat requires. This section will cover Xcode Build Setting requirements for a command line application. 

### Xcode Build Settings - Packaging Section
+ set 'Create Info.plist Section in Binary' to Yes. This step is only needed for Command Line applications.
+ set 'Generate Info.plist File' to Yes.
+ set 'Product Bundle Identifier' to the name of your product bundle - a unique reverse domain name typically: com.bugsplat.BugSplatTest-macOS-Tool-CPlusPlus
+ set 'Product Name' to the name of your product: 'BugSplatTest-macOS-Tool-CPlusPlus'

### Xcode Build Settings - Versioning Section
+ set 'Current Product Version' to the product version, typically and Integer: 1
+ set 'Marketing Version' to the product marketing version, typically two or three dotted semantic version: 1.0 or 1.0.0

### Linking framework(s)
BugSplat.xcframework must be linked with any iOS or macOS application using BugSplat. Additionally, for a command line application, Apple's AppKit framework must also be linked, due to the requirement of programmatically and manually posting NSApplicationDidFinishLaunchingNotification NSNotification. For any command line application to launch on macOS, the compiled binary must be able to find at compile time, link time, and runtime, BugSplat.xcframework as well as Apple's AppKit framework. 
