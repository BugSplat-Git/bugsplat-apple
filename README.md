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

BugSplat 9 for Apple platforms is a Swift API over [bugsplat-native](https://github.com/BugSplat-Git/bugsplat-native), BugSplat's cross-platform crash reporter built on Crashpad. It reports crashes, hangs, caught errors and user feedback from macOS, iOS and tvOS apps to [BugSplat](https://www.bugsplat.com).

On macOS everything that matters happens **out of process**: `BugSplatMonitor` captures the crash and writes the dump, `BugSplatReporter.app` shows the dialog and uploads the report, and the support-response page opens for the user. Your app only describes the report. On iOS and tvOS capture is in process and reports are sent at the next launch.

Version 9 is a new SDK, not an update: the API is Swift-first, the reporter is the same themeable one used on Windows and Linux, and the previous in-process crash reporter is gone. See [Migrating from 2.x and 3.x](#migrating-from-2x-and-3x) if you are upgrading.

## Requirements 📋

- macOS 13 or later, iOS 15 or later, tvOS 15 or later (beta)
- Xcode 15.3 or later (Swift 5.10)
- Mac Catalyst is not supported

## Integration 🏗️

### Swift Package Manager

Add `https://github.com/BugSplat-Git/bugsplat-apple` to your project's package dependencies and add the `BugSplat` product to your **application target**. The package brings `BugSplatNative.xcframework` with it; Xcode embeds it in your app and signs it with your identity. On macOS the framework carries `BugSplatMonitor` and `BugSplatReporter.app` in its `Helpers` directory, so nothing else needs to ship.

```swift
dependencies: [
    .package(url: "https://github.com/BugSplat-Git/bugsplat-apple.git", from: "9.0.0")
]
```

> [!IMPORTANT]
> If only an intermediate framework target depends on the package, also add the `BugSplat` product to the app target so the native framework gets embedded and re-signed. A missing framework surfaces as `BugSplatError.monitorNotFound` / `.reporterNotFound` from `BugSplat.start`; there is no silent in-process fallback on macOS.

### CocoaPods

```ruby
pod 'BugSplat', '~> 9.0'
```

### Manual

Download `BugSplatNative.xcframework.zip` from the [Releases](https://github.com/BugSplat-Git/bugsplat-apple/releases) page, add it to *Frameworks, Libraries, and Embedded Content* (Embed & Sign), and add `Sources/BugSplat` to your project.

## Usage 🧑‍💻

### Configuration

Add your database to `Info.plist` (or pass it to `start`):

```xml
<key>BugSplatDatabase</key>
<string>DATABASE_NAME</string>
```

> [!NOTE]
> Sandboxed macOS apps need *Outgoing Connections (Client)*. App Sandbox / Mac App Store apps: the out-of-process handshake is being validated; until then use the SDK in non-sandboxed builds.

### Start

```swift
import BugSplat

var options = BugSplat.Options()
options.uploadPolicy = .dialog                       // .quiet, or .manual to drain reports yourself
options.hangDetection = .init(timeout: 5, policy: .report)
options.attributes = ["build": "nightly"]

do {
    try BugSplat.start(options: options)             // database, application and version from Info.plist
} catch {
    print("BugSplat could not start: \(error)")      // a packaging error, see BugSplatError
}
```

SwiftUI:

```swift
@main
struct MyApp: App {
    init() { try? BugSplat.start() }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

Objective-C:

```objc
@import BugSplat;

BugSplatConfiguration *config = [BugSplatConfiguration new];
config.uploadPolicy = BugSplatUploadPolicyDialog;
NSError *error = nil;
[BugSplat startWithDatabase:nil application:nil version:nil configuration:config error:&error];
```

### Describe the report

Every one of these can change at any time after `start`, from any thread. What is set at the instant of the crash is what the report carries.

```swift
BugSplat.user = "ada@example.com"
BugSplat.email = "ada@example.com"
BugSplat.key = "level-3"                              // selects the localized support response
BugSplat.userDescription = "what the user was doing"
BugSplat.notes = "feature flags: a,b"
try BugSplat.setAttribute("branch", value: "main")    // up to 64, searchable in the dashboard
try BugSplat.addAttachment(logFileURL)                // up to 24 files, copied at crash time
print(BugSplat.environment!)                          // "macOS 15.2 (24C101) arm64", overridable
```

`environment` is a first-class report property, like `user` and `email`: the SDK fills it with the OS, build and hardware it runs on and sends it with every report.

### Reports that are not crashes

```swift
try BugSplat.captureReport()                          // a dump of the live process; the app keeps running

let result = try await BugSplat.postFeedback(title: "Login button unresponsive",
                                             description: "Nothing happens on the first tap",
                                             attachments: [screenshotURL])
print(result.crashId, result.infoURL ?? "")

do { try riskyOperation() } catch {
    try await BugSplat.post(error)                    // a structured report with the call stack
}
```

`BugSplat.Report` builds structured reports by hand (threads, frames, modules, registers) for engines and script runtimes; `Report(exception:)` takes an `NSException`.

### Hang detection

With `options.hangDetection` set, the watchdog pings the main dispatch queue. Once it stops answering for `timeout`, a report of the whole process is captured out of process (`reportKind = hang`); with `.report` the app continues, with `.reportAndTerminate` the macOS dialog offers Wait / Close and terminates the app on Close. Processes without a main run loop call `BugSplat.heartbeat()`; extra threads register with `BugSplat.watchThread(name:)`.

### The macOS dialog

`BugSplatReporter.app` shows the BugSplat dialog after the crash: description, name and email, the report files, "always send", then the support-response page. Its look and strings come from `theme/theme.json` and `theme/strings.<locale>.json` inside the framework's `Helpers`; point `options.themeDirectory` at your own copy to brand it. See bugsplat-native's [THEME.md](https://github.com/BugSplat-Git/bugsplat-native/blob/main/reporter/docs/THEME.md).

### iOS and tvOS

Crash capture is in process. At the next launch, reports from the previous session are handled according to the upload policy: uploaded silently (`.quiet`, or once the user chose "Always Send"), left for you (`.manual`), or offered through an in-app prompt with Send / Don't Send / Always Send and name, email and description fields (`.dialog`). `BugSplatDelegate` hears about the prompt and every upload:

```swift
BugSplat.delegate = self

func bugSplatDidSendReport(crashId: Int64, infoURL: URL?, folder: URL) {
    if let infoURL { show(infoURL) }                  // the support response for this crash
}
```

### Pending reports

Under `.manual` (any platform) the app owns the reports:

```swift
for report in BugSplat.pendingReports() {             // kind, crashTime, attributes, attachments, ...
    let result = try await BugSplat.send(report, description: "sent from settings")
    // or: try BugSplat.discard(report)
}
try BugSplat.postPendingReports()                     // everything, silently, in the background
```

### Symbols

Upload your app's dSYMs after every archive with [symbol-upload](https://docs.bugsplat.com/education/faq/how-to-upload-symbol-files-with-symbol-upload); it converts them to the Breakpad `.sym` files the server symbolicates Crashpad reports with:

```sh
symbol-upload-macos -b DATABASE -a "My App" -v "1.2.3 (456)" -f "**/*.dSYM" -d "$ARCHIVE_DSYMS_PATH" -m
```

`Symbol_Upload_Examples/Build-Phase-symbol-upload.sh` shows a build-phase script. Keep bitcode off.

### Diagnostics

`BugSplat.logFileURL` is `BugSplat.log` inside the store (`~/Library/Application Support/BugSplat/<application>-<version>/`); it is the first place to look. `options.logHandler` receives the same lines.

## Migrating from 2.x and 3.x

Concepts carry over; names do not. There are no compatibility shims: old-style calls do not compile, and reports left behind by 2.x/3.x are not imported.

| 2.x / 3.x | 9.0 |
|---|---|
| `BugSplat.shared().start()` with properties set before it | `try BugSplat.start(database:application:version:options:)` |
| `bugSplatDatabase`, `applicationName`, `applicationVersion` | parameters of `start` (Info.plist defaults unchanged) |
| `userName`, `userEmail`, `appKey`, `notes` | `BugSplat.user`, `.email`, `.key`, `.notes`; plus `.userDescription`, `.environment` |
| `setValue(_:forAttribute:)` | `try BugSplat.setAttribute(_:value:)` |
| `BugSplatDelegate.attachments(for:sessionID:)`, `BugSplatAttachment` | `try BugSplat.addAttachment(url)` / `removeAttachment`, at any time; files are copied at crash time, so per-session files and `sessionID` are no longer needed |
| `autoSubmitCrashReport` | `options.uploadPolicy` (`.dialog` / `.quiet` / `.manual`) and `BugSplat.isQuietMode` |
| `enableHangDetection`, `hangDetectionThreshold`, `autoSubmitFatalHangReport` | `options.hangDetection = .init(timeout:policy:)`; non-fatal hangs are reported too |
| `postFeedback(title:description:userName:userEmail:appKey:attributes:attachments:completion:)` | `try await BugSplat.postFeedback(title:description:attachments:)` (user, email, key and attributes come from the session) |
| `bannerImage`, `askUserDetails`, `persistUserDetails`, `presentModally`, `expirationTimeInterval` | the reporter theme (`theme.json`) and `preferences.json` in the store |
| delegate `willSend` / `didFinishSending` / `didFail` (macOS) | none: the dialog and upload run after the app has died; on iOS/tvOS see `BugSplatDelegate` |
| PLCrashReporter `.crashlog` reports (type 13) | Crashpad minidumps (type 5); symbolication from `.sym` files produced from your dSYMs |

## Examples 🧑‍🏫

- `Examples/macOS-HelloCrash`: a command-line app (`swift run HelloCrash [crash|capture|feedback|error|hang] [quiet|manual]`).
- `Examples/iOS-SwiftUI`: a SwiftUI app with crash, capture, feedback and hang buttons and the in-app prompt.

## Contributing 🤝

```sh
git clone https://github.com/BugSplat-Git/bugsplat-apple && cd bugsplat-apple
scripts/build-native.sh      # clones bugsplat-native, builds Crashpad + the native library, assembles Frameworks/BugSplatNative.xcframework
swift build && swift test    # see Tests/README.md for the runtime test
open Package.swift           # or use it from Xcode
```

The native side (C ABI, monitor, reporter, uploader) lives in [bugsplat-native](https://github.com/BugSplat-Git/bugsplat-native); this repository is the Swift layer, the iOS/tvOS prompt and the packaging. `bindings/swift/make-xcframework.sh` over there defines the framework layout.

### Releasing

Run the `release` workflow with the bugsplat-native ref to build. It publishes `BugSplatNative.xcframework.zip`, rewrites `Package.swift` to the release URL and checksum, bumps the podspec, commits and tags the version from bugsplat-native's `VERSION` file.
