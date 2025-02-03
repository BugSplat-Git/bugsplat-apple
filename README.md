[![bugsplat-github-banner-basic-outline](https://user-images.githubusercontent.com/20464226/149019306-3186103c-5315-4dad-a499-4fd1df408475.png)](https://bugsplat.com)
<br/>
# <div align="center">BugSplat</div> 
### **<div align="center">Crash and error reporting built for busy developers.</div>**
<div align="center">
    <a href="https://twitter.com/BugSplatCo">
        <img alt="Follow @bugsplatco on Bluesky" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fpublic.api.bsky.app%2Fxrpc%2Fapp.bsky.actor.getProfile%2F%3Factor%3Dbugsplatco.bsky.social&query=%24.followersCount&style=social&logo=bluesky&label=Follow%20%40bugsplatco.bsky.social">
    </a>
    <a href="https://discord.gg/bugsplat">
        <img alt="Join BugSplat on Discord" src="https://img.shields.io/discord/664965194799251487?label=Join%20Discord&logo=Discord&style=social">
    </a>
</div>

<br/>

## Introduction 👋

The BugSplat.xcframework enables posting crash reports from iOS, macOS, and Mac Catalyst applications to BugSplat. Visit [bugsplat.com](https://www.bugsplat.com) for more information and to sign up for an account.

## Requirements 📋

- BugSplat for iOS supports iOS 13 and later.
- BugSplat for macOS supports macOS 10.13 and later.

## Integration 🏗️

BugSplat supports multiple methods for installing the xcfamework in a project.

### Swift Package Manager (SPM)

TODO BG

### Manual Setup

To use this xcframework in your project manually you may:

1. Download the latest release from the [Releases](https://github.com/BugSPlat-Git/bugsplat-apple/releases) page. The release will contain a zip file with the xcframework.
2. Unzip the archive.
3. In Xcode, select your app target, then go to the General tab, scroll down to Framework, Libraries, and Embedded Content, then click the "+" and navigate to locate the unzipped BugSplat.xcframework. Once added, select Embed & Sign.

## Usage 🧑‍💻

#### Configuration

BugSplat requires a few Xcode configuration steps in order integrate the xcframework with your BugSplat account

- Add the following case sensitive key to your app's Info.plist replacing DATABASE_NAME with your customer specific BugSplat database name.

  ```xml
  <key>BugSplatDatabase</key>
  <string>DATABASE_NAME</string>
  ```

  NOTE: For macOS apps, you must enable Outgoing network connections (client) in the Signing & Capabilities of the Target.

#### Symbol Upload

- You must upload an archive containing your app's binary and symbols to the BugSplat server in order to symbolicate crash reports. There are scripts to help with this.

  - Create a ~/.bugsplat.conf file to store your BugSplat credentials

    ```ini
    BUGSPLAT_USER="<username>"
    BUGSPLAT_PASS="<password>"
    ```

  - Download BugSplat's cross-platform tool `symbol-upload-macos`. See https://docs.bugsplat.com/education/faq/how-to-upload-symbol-files-with-symbol-upload for documentation and a link to download a prebuilt binary, or from github.

    NOTE: Due to tightened macOS security features, this `symbol-upload-macos` may need to be manually approved before it will run on your Mac.
    Additionally, please ensure Build Setting ENABLE_USER_SCRIPT_SANDBOXING is set to NO or delete this Build Setting to accept the default NO. Otherwise the `symbol-upload-macos` will likely fail to upload the symbols due to a file system restriction to package up the dSYM files to upload.

  - Several options exist to integrate `symbol-upload-macos` into the app build process.

    - Create an Xcode build-phase script to upload dSYM files after every build. See example script Symbol_Upload_Examples/Build-Phase-symbol-upload.sh
    - Create an Xcode Archive post-action script in the target's Build Scheme in order to to upload dSYM files after the app is archived and ready for submission to TestFlight or App Store. See example script Symbol_Upload_Examples/Archive-post-action-upload.sh
    - Manually upload an xcarchive generated by Xcode to your BugSplat portal.

    NOTE: For build-phase script to create dSYM files, change Build Settings DEBUG_INFORMATION_FORMAT from DWARF to DWARF with dSYM File.
    NOTE: See inline notes within each script for modifications to Xcode Build Settings required for each script to work.

#### Initialization

- Several iOS and macOS test app examples are included within the `Example_Apps` folder, to show how simple and quickly BugSplat can be integrated into an app, and ready to submit crash reports.

#### Crash Reporter UI Customization

**Custom banner image**

- BugSplat fo macOS provides the ability to configure a custom image to be displayed in the crash reporter UI for branding purposes. The image view dimensions are 440x110 and will scale down proportionately. There are 2 ways developers can provide an image:

    1. Set the image property directly on BugSplat
    2. Provide an image named `bugsplat-logo` in the main app bundle or asset catalog

**User details**

- Set `askUserDetails` to `NO` in order to prevent the name and email fields from displaying in the crash reporter UI. Defaults to `YES`.

**Auto submit**

- By default, BugSplat will auto submit crash reports for iOS and will prompt the end user to submit a crash report for macOS. This default can be changed using a BugSplat property autoSubmitCrashReport. Set `autoSubmitCrashReport` to `YES` in order to send crash reports to the server automatically without presenting the crash reporter dialogue.

**Persist user details**

- Set `persistUserDetails` to `YES` to save and restore the user's name and email when presenting the crash reporter dialogue. Defaults to `NO`.

**Expiration time**

- Set `expirationTimeInterval` to a desired value (in seconds) whereby if the difference in time between when the crash occurred and next launch is greater than the set expiration time, auto send the report without presenting the crash reporter dialogue. Defaults to `-1`, which represents no expiration.

#### Attachments

Bugsplat supports uploading attachments with crash reports. There's a delegate method provided by `BugSplatDelegate` that can be implemented to provide attachments to be uploaded.

#### Bitcode

Bitcode was introduced by Apple to allow apps sent to the App Store to be recompiled by Apple itself and apply the latest optimization. Bitcode has now been officially deprecated by Apple and should be removed or disabled. If Bitcode is enabled, the symbols generated for your app in the store will be different than the ones from your own build system. We recommend that you disable bitcode in order for BugSplat to reliably symbolicate crash reports. Disabling bitcode significantly simplifies symbols management and currently doesn't have any known downsides for iOS apps.

#### Localization

For macOS, the BugSplat crash dialogue can be localized and supports 8 languages out of the box.

1. English
2. Finnish
3. French
4. German
5. Italian
6. Japanese
7. Norwegian
8. Swedish

Additional languages may be supported by adding the language bundle and strings file to `BugSplat.xcframework/macos-arm64_x86_64/BugSplatMac.framework/Versions/A/Frameworks/HockeySDK.framework/Resources/`

#### Sample Applications

`Example_Apps` includes several iOS and macOS BugSplat Test apps. Integrating BugSpat only requires the xcframework, and a few lines of code.

# FIXME

1. Clone the [BugsplatMac repo](https://github.com/BugSplat-Git/).

1. Open an example Xcode project from Example_Apps. For iOS, set the destination to be your iOS device. After running from Xcode, stop the process and relaunch from iOS device directly.

1. Once the app launches, click the "crash" button when prompted.

1. Relaunch the app on the iOS device. At this point a crash report should be submitted to bugsplat.com

1. Visit BugSplat's [Crashes](https://app.bugsplat.com/v2/crashes) page. When prompted for credentials enter user "fred@bugsplat.com" and password "Flintstone". The crash you posted from BugsplatTester should be at the top of the list of crashes.

1. Click the link in the "Crash Id" column to view more details about your crash.

## Contributing 🤝

BugSplat is an open source project and we welcome contributions from the community. To configure a development environment, follow the instructions below.

### Prerequisites

> [!WARNING]
> This project requires Xcode Command Line Tools 15.x to build. Version 16.x will crash when building the project.

First, install `Xcode 15.4` by following this [link](https://developer.apple.com/download/more/?q=xcode%2015.4) and searching for `Xcode 15.4`. Download the zip file and copy `Xcode.app` to your Applications folder. If you already have Xcode installed create a new folder in Applications and copy `Xcode.app` to that folder. Rename `Xcode.app` to `Xcode-15.4.app`.

Open terminal and select the Command Line Tools for Xcode 15.4

```sh
sudo xcode-select -s /Applications/Xcodes/Xcode-15.4.app
```

Next, download and install [Git-LFS](https://git-lfs.com/). Once you've installed Git-LFS, run the following command to initialize it (you only need to do this once on your machine):

```sh
git lfs install
```

### Building

Clone this repository and all of the depenencies into a new `BugSplat` folder.

```sh
mkdir BugSplat
cd BugSplat
git clone https://github.com/BugSplat-Git/bugsplat-apple
git clone https://github.com/BugSplat-Git/HockeySDK-Mac
git clone https://github.com/BugSplat-Git/HockeySDK-iOS
git clone https://github.com/BugSplat-Git/plcrashreporter
```

Next, in the prescribed order, build each repo. If an error occurs in a specific repo, it
must be resolved before you can move to the next repo. This process was verified with
specific Apple Developer account for code signing. A different Apple Developer account
require adjusting the code signing within a given project.

1. Build PlCrashReporter

```sh
cd plcrashreporter
./makeXCFramework.sh
...
xcframework successfully written out to: .../BugSplat/plcrashreporter/xcframeworks/CrashReporter.xcframework
```

2. Build HockeySDK-Mac

```sh
cd HockeySDK-Mac
./makeXCFramework.sh
...
xcframework successfully written out to: .../BugSplat/HockeySDK-Mac/xcframeworks/HockeySDK-macOS.xcframework
```

3. Build HockeySDK-iOS

```sh
cd HockeySDK-iOS
./makeXCFramework.sh
...
xcframework successfully written out to: .../BugSplat/HockeySDK-iOS/xcframeworks/HockeySDK.xcframework
```

4. Build bugsplat-apple

```sh
cd bugsplat-apple
./makeXCFramework.sh
...
xcframework successfully written out to: .../BugSplat/bugsplat-apple/xcframeworks/BugSplat.xcframework
```

If all goes smoothly, BugSplat.xcframework will be the result in the xcframeworks folder
of the bugsplat-apple repo.
