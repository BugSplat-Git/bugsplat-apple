[![bugsplat-github-banner-basic-outline](https://user-images.githubusercontent.com/20464226/149019306-3186103c-5315-4dad-a499-4fd1df408475.png)](https://bugsplat.com)
<br/>

# <div align="center">BugSplat</div>

### **<div align="center">Crash and error reporting built for busy developers.</div>**

<div align="center">
    <a href="https://bsky.app/profile/bugsplatco.bsky.social"><img alt="Follow @bugsplatco on Bluesky" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fpublic.api.bsky.app%2Fxrpc%2Fapp.bsky.actor.getProfile%2F%3Factor%3Dbugsplatco.bsky.social&query=%24.followersCount&style=social&logo=bluesky&label=Follow%20%40bugsplatco.bsky.social"></a>
    <a href="https://discord.gg/bugsplat"><img alt="Join BugSplat on Discord" src="https://img.shields.io/discord/664965194799251487?label=Join%20Discord&logo=Discord&style=social"></a>
</div>

<br/>

## Introduction 👋

The BugSplat.xcframework enables posting crash reports from iOS, macOS, and Mac Catalyst applications to BugSplat. Visit [bugsplat.com](https://www.bugsplat.com) for more information and to sign up for an account.

## Requirements 📋

- BugSplat for iOS supports iOS 13 and later.
- BugSplat for macOS supports macOS 11.5 and later.

## Integration 🏗️

The BugSplat crash reporting SDK can be integrated into your project via the following methods:
- Using Swift Package Manager
- Using CocoaPods
- Manually adding xcframeworks

### Swift Package Manager (SPM)

Add the following URL to your project's `Additional Package Dependencies`:

```sh
https://github.com/BugSplat-Git/bugsplat-apple
```

### CocoaPods

Add the following to your `Podfile`:

```ruby
pod 'BugSplat', '~> 3.0'
```

Then run `pod install`.

### Manually Add xcframeworks

To manually integrate BugSplat into your Xcode project, BugSplat.xcframework needs to be added and configured within Xcode.

1. Download the latest released xcframework (BugSplat.xcframework.zip) from the [Releases](https://github.com/BugSPlat-Git/bugsplat-apple/releases) page. The zip will contain BugSplat.xcframework.
2. Unzip the archive.
3. In Xcode, select your app target, then go to the General tab, scroll down to Framework, Libraries, and Embedded Content, then click the "+" and navigate to where you unzipped the archive in step 2. Select BugSplat.xcframework, then tap the "Add" button. Once added, select Embed & Sign for the xcframework.

### Troubleshooting: "Library not loaded" / "different Team IDs" on macOS

If your app integrates BugSplat with Swift Package Manager and crashes at launch with:

```
dyld: Library not loaded: @rpath/BugSplat.framework/Versions/A/BugSplat
Reason: ... code signature ... not valid for use in process:
mapping process and mapped file (non-platform) have different Team IDs
```

the package resolved and built correctly — this is a code-signing issue at load time.
`BugSplat.framework` ships with an ad-hoc (linker) signature and no Team ID. When your
app is signed with your team's identity and has the Hardened Runtime's Library
Validation enabled, `dyld` refuses to load any non-platform library that is not signed
with the same Team ID.

This typically happens when only an **intermediate framework target** depends on the
BugSplat package. Xcode links against the unsigned copy of `BugSplat.framework` in the
build products directory, but never embeds and re-signs it into the app bundle —
embedding only happens for package products attached to an **application** target.

**Fix:** also add the BugSplat package product to your app target —
select the app target, General → *Frameworks, Libraries, and Embedded Content* → `+` →
BugSplat. Xcode then embeds the framework in the app bundle and re-signs it with your
signing identity, which satisfies Library Validation.

## Usage 🧑‍💻

### Configuration

BugSplat requires a few Xcode configuration steps to integrate the xcframework with your BugSplat account.

Add the following case-sensitive key to your app's `Info.plist`, replacing `DATABASE_NAME` with your customer-specific BugSplat database name.

```xml
<key>BugSplatDatabase</key>
<string>DATABASE_NAME</string>
```

> [!NOTE]
> For macOS apps, you must enable Outgoing network connections (client) in the Signing & Capabilities of the Target.

### Symbol Upload

To symbolicate crash reports, you must upload your app's `dSYM` files to the BugSplat server. There are scripts to help with this.

Download BugSplat's cross-platform tool, [symbol-upload-macos](https://docs.bugsplat.com/education/faq/how-to-upload-symbol-files-with-symbol-upload) for Apple Silicon by entering the following command in your terminal.

```sh
curl -sL -O "https://app.bugsplat.com/download/symbol-upload-macos"
```

Alternatively, you can download the Intel version via the following command.

```sh
curl -sL -O "https://app.bugsplat.com/download/symbol-upload-macos-intel"
```

Make `symbol-upload-macos` executable

```sh
chmod +x symbol-upload-macos
```

Several options exist to integrate `symbol-upload-macos` into the app build process.

- Create an Xcode build-phase script to upload dSYM files after every build. See example script [Symbol_Upload_Examples/Build-Phase-symbol-upload.sh](Symbol_Upload_Examples/Build-Phase-symbol-upload.sh)

- Create an Xcode Archive post-action script in the target's Build Scheme to upload dSYM files after the app is archived and ready for submission to TestFlight or the App Store. See example script [Symbol_Upload_Examples/Archive-post-action-upload.sh](Symbol_Upload_Examples/Archive-post-action-upload.sh)
- Manually upload an `xcarchive` or `dSYM` file generated by Xcode via BugSplat's [Versions](https://app.bugsplat.com/v2/versions) page.

> [!NOTE]
> For the build-phase script to create dSYM files, change Build Settings `DEBUG_INFORMATION_FORMAT` from `DWARF` to `DWARF with dSYM File`. See inline notes within each script for modifications to Xcode Build Settings required for each script to work.

Please refer to our [documentation](https://docs.bugsplat.com/education/faq/how-to-upload-symbol-files-with-symbol-upload) to learn more about how to use `symbol-upload-macos`.

### Initialization

Several iOS and macOS test app examples are included within the [Example_Apps](Example_Apps) folder to show how simple and quickly BugSplat can be integrated into an app and ready to submit crash reports.

You can instantiate BugSplat by following the language-specific examples below.

#### Swift (UIKit)

```swift
import BugSplat

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize BugSplat
        BugSplat.shared().delegate = self
        BugSplat.shared().autoSubmitCrashReport = false
        BugSplat.shared().start()

        return true
    }
}

extension AppDelegate: BugSplatDelegate {
    // MARK: BugSplatDelegate
    func bugSplatWillSendCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillSendCrashReportsAlways(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatDidFinishSendingCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillCancelSendingCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillShowSubmitCrashReportAlert(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplat(_ bugSplat: BugSplat, didFailWithError error: Error) {
        print("\(#file) - \(#function)")
    }
}
```

#### Swift (SwiftUI)

```swift
import BugSplat

@main
struct BugSplatTestSwiftUIApp: App {
    private let bugSplat = BugSplatInitializer()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@objc class BugSplatInitializer: NSObject, BugSplatDelegate {
    override init() {
        super.init()
        BugSplat.shared().delegate = self
        BugSplat.shared().autoSubmitCrashReport = false
        BugSplat.shared().start()
    }

    // MARK: BugSplatDelegate
    func bugSplatWillSendCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillSendCrashReportsAlways(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatDidFinishSendingCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillCancelSendingCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillShowSubmitCrashReportAlert(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplat(_ bugSplat: BugSplat, didFailWithError error: Error) {
        print("\(#file) - \(#function)")
    }
}
```

#### Obj-C

```objc
#import <BugSplat/BugSplat.h>

@interface AppDelegate () <BugSplatDelegate>
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Initialize BugSplat
    [[BugSplat shared] setDelegate:self];
    [[BugSplat shared] setAutoSubmitCrashReport:NO];
    [[BugSplat shared] start];
}

#pragma mark - BugSplatDelegate

- (void)bugSplatWillSendCrashReport:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillSendCrashReport called");
}

- (void)bugSplatWillSendCrashReportsAlways:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillSendCrashReportsAlways called");
}

- (void)bugSplatDidFinishSendingCrashReport:(BugSplat *)bugSplat {
    NSLog(@"bugSplatDidFinishSendingCrashReport called");
}

- (void)bugSplatWillCancelSendingCrashReport:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillCancelSendingCrashReport called");
}

- (void)bugSplatWillShowSubmitCrashReportAlert:(BugSplat *)bugSplat {
    NSLog(@"bugSplatWillShowSubmitCrashReportAlert called");
}

- (void)bugSplat:(BugSplat *)bugSplat didFailWithError:(NSError *)error {
    NSLog(@"bugSplat:didFailWithError: %@", [error localizedDescription]);
}
```

### Attributes

BugSplat supports custom attributes that can be added to a crash report. These attributes are searchable in the BugSplat dashboard.

```swift
BugSplat.shared().setValue("Value of Attribute", forAttribute: "AttributeName")
```

```objc
[[BugSplat shared] setValue:@"Value of Attribute" forAttribute:@"AttributeName"];
```

It is important to understand how attributes are set, as well as if and when attributes will be included in a crash report.

Attributes and their associated values are programmatically set at any time while an app is running. Attributes are unique `NSString` keys so there can only be one attribute of a given name in any given set of attributes. Every time BugSplat's `setValue:forAttribute:` API is called, this attribute/value pair will be added to an `NSDictionary<NSString *, NSString *>`. If the app session terminates due to a crash, the attributes are handled as follows:

    1. The attributes set during the session are recorded with the crash report at the moment the crash occurs.
    2. Upon the next launch, the recorded attributes are read back from the crash report and sent as form fields on the crash upload request.
    3. Attributes are NOT sent as an attachment, on any platform, so they never consume an attachment slot and are never suppressed by attachments returned from `BugSplatDelegate`.

Put another way, attributes and their values are only valid for the lifetime of the app session and are only used in a crash report if the crash occurs during that app session. Any attributes set in the prior app session are uploaded with the crash report that is processed during the next launch of the app. If the app terminates normally, any attributes recorded during the prior `normal` app session are discarded.


Please take a look at the framework-specific [sample applications](#sample-applications-) for more examples showing how to use attributes.

### User Feedback

BugSplat supports submitting user feedback (non-crash reports) from your application. Feedback is uploaded using crash type ID 36 (`User.Feedback`) and appears in the BugSplat dashboard alongside crash reports.

**Swift:**

```swift
BugSplat.shared().postFeedback(
    title: "Login button unresponsive",
    description: "The login button doesn't respond on the first tap.",
    userName: nil,
    userEmail: nil,
    appKey: nil,
    attachments: nil
) { error in
    if let error {
        print("Feedback failed: \(error.localizedDescription)")
    } else {
        print("Feedback submitted successfully!")
    }
}
```

**Obj-C:**

```objc
[[BugSplat shared] postFeedback:@"Login button unresponsive"
                    description:@"The login button doesn't respond on the first tap."
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
```

All parameters except `title` are optional. When `userName`, `userEmail`, or `appKey` are nil, BugSplat falls back to the corresponding property values set on the `BugSplat` singleton. You can also include file attachments using an array of `BugSplatAttachment` objects.

### Crash Reporter Customization

There are several ways to customize your BugSplat crash reporter.

#### Custom Banner Image

- BugSplat for macOS provides the ability to configure a custom image to be displayed in the crash reporter UI for branding purposes. The image view dimensions are 440x110 and will scale down proportionately. There are 2 ways developers can provide an image:

  1. Set the image property directly on BugSplat
  2. Provide an image named `bugsplat-logo` in the main app bundle or asset catalog

#### User Details

- BugSplat for macOS provides the ability for the user to provide a name and email when submitting a crash report. To provide the name and email, set `askUserDetails` to `NO` to prevent the name and email fields from displaying in the crash reporter UI. Defaults to `YES`.

#### Auto Submit

- By default, BugSplat will auto-submit crash reports for iOS and prompt the end user to submit a crash report for macOS. This default can be changed using a BugSplat property autoSubmitCrashReport. Set `autoSubmitCrashReport` to `YES` in order to send crash reports to the server automatically without presenting the crash reporter dialogue.

#### Persist User Details

- BugSplat for macOS provides the ability to persist the user name and email entered in a crash reporter UI. Set `persistUserDetails` to `YES` to save and restore the user's name and email when presenting the crash reporter dialogue. Defaults to `NO`.

#### Expiration Time

- Set `expirationTimeInterval` to a desired value (in seconds) whereby if the difference in time between when the crash occurred and the next launch is greater than the set expiration time, auto-send the report without presenting the crash reporter dialogue. Defaults to `-1`, which represents no expiration.

#### Application Name and Version

By default, BugSplat uses values from your app's `Info.plist` (`CFBundleDisplayName`/`CFBundleName` for application name and `CFBundleShortVersionString` for version). You can override these values programmatically before calling `start`:

**Swift:**

```swift
BugSplat.shared().applicationName = "MyCustomAppName"
BugSplat.shared().applicationVersion = "2.0.0-beta"
BugSplat.shared().start()
```

**Obj-C:**

```objc
[[BugSplat shared] setApplicationName:@"MyCustomAppName"];
[[BugSplat shared] setApplicationVersion:@"2.0.0-beta"];
[[BugSplat shared] start];
```

> [!NOTE]
> These values must be set before calling `start`. Any changes made after `start` is invoked will be ignored.

#### Application Key

Set an `appKey` to identify your application build, environment, or user locale. In the BugSplat dashboard, you can configure custom localized support responses for crash groups based on the `appKey` value using the "Support Response" button on the Crash Group page. See [Support Responses](https://docs.bugsplat.com/introduction/production/setting-up-custom-support-responses) for more information.

**Swift:**

```swift
BugSplat.shared().appKey = "en-US"
```

**Obj-C:**

```objc
[[BugSplat shared] setAppKey:@"en-US"];
```

#### Notes

Add arbitrary additional data to include with crash reports. Notes can also be modified in the BugSplat dashboard after a crash is submitted.

**Swift:**

```swift
BugSplat.shared().notes = "Debug build, feature-x enabled"
```

**Obj-C:**

```objc
[[BugSplat shared] setNotes:@"Debug build, feature-x enabled"];
```

#### Attachments

BugSplat supports uploading attachments with crash reports. There are delegate methods provided by `BugSplatDelegate` that can be implemented to provide attachments to be uploaded. Implement `attachmentsForBugSplat:sessionID:` (Swift: `attachments(for:sessionID:)`) to return any number of attachments; it is supported on both macOS and iOS. The single-attachment `attachmentForBugSplat:` variants remain available for existing integrations. Attachments are independent of [Attributes](#attributes) — attributes are sent as form fields on the upload request, not as an attachment.

#### Associating Per-Session Files with Crash Reports

Crash reports are processed and uploaded at the **next launch** after a crash — not at crash time. By the time `BugSplatDelegate` asks your app for attachments, your app is running a new session, so a fixed file path that gets overwritten each launch (e.g. `app.log`) no longer contains the crashed session's data.

To make this association reliable, BugSplat provides a per-launch session ID:

- `BugSplat.shared().sessionID` — a `UUID` generated when the `BugSplat` instance is first created (e.g. via `BugSplat.shared()`), stable for the lifetime of the process, and readable before or after `start()` is called.
- The ID is embedded into any crash report captured during that session, and sessionID-aware delegate callbacks pass the **crashed** session's ID back to you at the next launch:
  - `attachments(for:sessionID:)` / `attachment(for:sessionID:)` (Obj-C: `attachmentsForBugSplat:sessionID:` / `attachmentForBugSplat:sessionID:`)
  - `applicationLog(for:sessionID:)` (Obj-C: `applicationLogForBugSplat:sessionID:`)
  - `bugSplatWillSendCrashReport(_:sessionID:)` (Obj-C: `bugSplatWillSendCrashReport:sessionID:`)
  - `bugSplatDidFinishSendingCrashReport(_:sessionID:)` (Obj-C: `bugSplatDidFinishSendingCrashReport:sessionID:`)
  - `bugSplat(_:didFailWithError:sessionID:)` (Obj-C: `bugSplat:didFailWithError:sessionID:`)

When a sessionID-aware method is implemented, it is called instead of its legacy counterpart. The `sessionID` parameter is `nil` for crash reports recorded by SDK versions that predate session tracking.

The recommended pattern — name session-scoped files after the session ID so the file name itself is the mapping:

**Swift:**

```swift
// 1. After start(), write this session's log to a file named after the session ID.
//    A fixed path that is overwritten each launch cannot be recovered later.
bugSplat.start()
let logURL = logsDirectory.appendingPathComponent("\(bugSplat.sessionID.uuidString).log")

// 2. At the next launch after a crash, return the crashed session's log.
func attachment(for bugSplat: BugSplat, sessionID: UUID?) -> BugSplatAttachment? {
    guard let sessionID,
          let data = try? Data(contentsOf: logsDirectory.appendingPathComponent("\(sessionID.uuidString).log")) else {
        return nil // report predates session tracking, or the log is gone
    }
    return BugSplatAttachment(filename: "session.log", attachmentData: data, contentType: "text/plain")
}

// 3. Once the report is delivered, the log is safe to delete. This is called once
//    per report, so cleanup is correct even when several queued reports upload at once.
func bugSplatDidFinishSendingCrashReport(_ bugSplat: BugSplat, sessionID: UUID?) {
    guard let sessionID else { return }
    try? FileManager.default.removeItem(at: logsDirectory.appendingPathComponent("\(sessionID.uuidString).log"))
}

// 4. On failure, keep the file - the SDK retries the upload on a future launch.
func bugSplat(_ bugSplat: BugSplat, didFailWithError error: Error, sessionID: UUID?) { }
```

**Obj-C:**

```objc
// 1. After start, write this session's log to a file named after the session ID.
[[BugSplat shared] start];
NSString *logPath = [logsDirectory stringByAppendingPathComponent:
    [NSString stringWithFormat:@"%@.log", [BugSplat shared].sessionID.UUIDString]];

// 2. At the next launch after a crash, return the crashed session's log.
- (NSArray<BugSplatAttachment *> *)attachmentsForBugSplat:(BugSplat *)bugSplat sessionID:(nullable NSUUID *)sessionID
{
    if (!sessionID) return @[]; // report predates session tracking
    NSString *path = [logsDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.log", sessionID.UUIDString]];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @[];
    return @[[[BugSplatAttachment alloc] initWithFilename:@"session.log"
                                           attachmentData:data
                                              contentType:@"text/plain"]];
}

// 3. Once the report is delivered, the log is safe to delete.
- (void)bugSplatDidFinishSendingCrashReport:(BugSplat *)bugSplat sessionID:(nullable NSUUID *)sessionID
{
    if (!sessionID) return;
    NSString *path = [logsDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.log", sessionID.UUIDString]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}
```

A few practical notes:

- **Use per-session file names.** The session ID can only recover a file that still exists at the next launch. Truncating or overwriting a single fixed path each launch destroys the crashed session's data before BugSplat can ask for it.
- **Prune old session files yourself.** Sessions that end normally never produce a crash report, so they never get a `didFinishSending` callback. Delete session files older than a few days at startup (never the current session's).
- **Hang reports work the same way.** A fatal hang persists its session ID alongside the report, and at the next launch BugSplat asks your delegate for that session's attachments and application log — and fires the upload lifecycle callbacks — exactly as it does for a crash, so the per-session log file shown above is attached to hang reports too. (Because a hang is captured while the main thread is unresponsive, this delegate work is deferred to the next launch rather than done at hang time, but that is transparent to your delegate implementation.)

Every app in `Example_Apps` demonstrates this pattern end to end.

#### Bitcode

Bitcode was introduced by Apple to allow apps sent to the App Store to be recompiled by Apple itself and apply the latest optimization. Bitcode has now been officially deprecated by Apple and should be removed or disabled. If Bitcode is enabled, the symbols generated for your app in the store will be different than the ones from your own build system. We recommend that you disable bitcode in order for BugSplat to reliably symbolicate crash reports. Disabling bitcode significantly simplifies symbols management and currently doesn't have any known downsides for iOS apps.

#### Localization

For macOS, the BugSplat crash dialogue can be localized and supports eight languages out of the box.

1. English
2. Finnish
3. French
4. German
5. Italian
6. Japanese
7. Norwegian
8. Swedish

Additional languages may be supported by adding the language bundle and strings file to `BugSplat.xcframework/macos-arm64_x86_64/BugSplat.framework/Versions/A/Resources/`

## Sample Applications 🧑‍🏫

`Example_Apps` includes several iOS and macOS BugSplat Test apps. Integrating BugSplat only requires the xcframework and a few lines of code.

1. Clone the [bugsplat-apple repo](https://github.com/BugSplat-Git/bugsplat-apple).

1. Open `BugSplat.xcworkspace` in Xcode. This workspace contains the SDK and all example apps. Select an example app scheme to run. For iOS, set the destination to be your iOS device. After running from Xcode, stop the process and relaunch from the iOS device directly.

1. Once the app launches, click the "crash" button when prompted.

1. Relaunch the app on the iOS device. At this point, a crash report should be submitted to bugsplat.com

1. Visit BugSplat's [Crashes](https://app.bugsplat.com/v2/crashes) page. When prompted for credentials, enter user `fred@bugsplat.com` and password `Flintstone`. The crash you posted from BugSplatTester should be at the top of the list of crashes.

1. Click the "Crash ID" link to view more details about your crash.

## Contributing 🤝

BugSplat is an open-source project, and we welcome contributions from the community. To configure a development environment, follow the instructions below.

### Development

Clone this repository and open the workspace:

```sh
git clone https://github.com/BugSplat-Git/bugsplat-apple
cd bugsplat-apple
open BugSplat.xcworkspace
```

The workspace contains the SDK frameworks, test targets, and example apps. Use the `BugSplatMacTests` or `BugSplatIOSTests` schemes to run unit tests.

### Building xcframework

To build a distributable `BugSplat.xcframework`:

```sh
./makeXCFramework.sh
...
xcframework successfully written out to: .../bugsplat-apple/xcframeworks/BugSplat.xcframework
```

If all goes smoothly, `BugSplat.xcframework` will be the result in the xcframeworks folder.

### Releasing

To release a new version of BugSplat.xcframework, push a new tag to the `main` branch. The [release](.github/workflows/release.yml) workflow will build the xcframework, update `Package.swift`, and publish the zipped archive to the [Releases](https://github.com/BugSplat-Git/bugsplat-apple/releases) page.
