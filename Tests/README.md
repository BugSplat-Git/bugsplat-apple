# BugSplat Unit Tests

This directory contains unit tests for the BugSplat Apple SDK.

## Test Structure

```
Tests/
└── BugSplatTests/
    ├── BugSplatUtilitiesTests.m    # XML utility function tests
    ├── BugSplatZipHelperTests.m    # ZIP creation and MD5 hash tests
    ├── BugSplatAttachmentTests.m   # Attachment model tests
    ├── BugSplatUploadServiceTests.m # Upload service tests with mocked networking
    ├── BugSplatTests.m             # Core BugSplat class tests
    ├── MockURLSession.h/.m         # Mock URL session for network testing
    ├── MockCrashReporter.h/.m      # Mock crash reporter
    ├── MockCrashStorage.h/.m       # Mock file storage
    ├── MockUserDefaults.h/.m       # Mock user defaults
    ├── MockBundle.h/.m             # Mock bundle for Info.plist
    └── Info.plist                  # Test bundle Info.plist
```

## Adding Test Target to Xcode Project

To add the test target to your Xcode project:

### Option 1: Using Xcode UI (Recommended)

1. Open `BugSplat.xcodeproj` in Xcode
2. Select the project in the Navigator
3. Click the `+` button at the bottom of the targets list
4. Choose `Unit Testing Bundle`
5. Configure:
   - Product Name: `BugSplatMacTests`
   - Target to be Tested: `BugSplatMac`
   - Language: `Objective-C`
6. Click Finish
7. Delete the auto-generated test file
8. Add existing files from `Tests/BugSplatTests/` to the test target:
   - Select all `.m` files in `Tests/BugSplatTests/`
   - Right-click → "Add Files to BugSplat..."
   - Ensure `BugSplatMacTests` is checked as the target
9. Add the main source files to the test target (for testing internal methods):
   - Select the test target in project settings
   - Go to Build Phases → Compile Sources
   - Add: `BugSplat.m`, `BugSplatUtilities.m`, `BugSplatZipHelper.m`, `BugSplatAttachment.m`, `BugSplatUploadService.m`
10. Configure Header Search Paths:
    - In Build Settings, add to Header Search Paths:
      - `$(PROJECT_DIR)` (recursive)
      - `$(PROJECT_DIR)/Vendor/PLCrashReporter/CrashReporter.xcframework/macos-arm64_x86_64/CrashReporter.framework/Headers`

### Option 2: For iOS Tests

Repeat the above steps but:
- Product Name: `BugSplatTests`
- Target to be Tested: `BugSplat`
- Set Destination to iOS

## Running Tests

### From Xcode
- Press `Cmd+U` to run all tests
- Or use Product → Test

### From Command Line
```bash
# Run macOS tests
xcodebuild test -project BugSplat.xcodeproj -scheme BugSplatMac -destination 'platform=macOS'

# Run iOS tests
xcodebuild test -project BugSplat.xcodeproj -scheme BugSplat -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Test Coverage

The tests cover:

### BugSplatUtilities (XML Handling)
- XML entity name validation (`isValidXMLEntity`)
- XML special character escaping
- CDATA and comment block preservation
- Token pair range parsing

### BugSplatZipHelper
- ZIP archive creation (single and multiple files)
- MD5 hash calculation
- ZIP structure validation
- Compression of various data types

### BugSplatAttachment
- Initialization with various content types
- NSSecureCoding round-trip serialization
- Binary data handling

### BugSplatUploadService
- Three-step upload flow (presigned URL → S3 → commit)
- Error handling (network errors, rate limiting, server errors)
- Metadata inclusion in uploads
- Attachment handling

### BugSplat (Core)
- Property resolution (database, app name, version)
- User defaults persistence (userName, userEmail)
- Attribute management
- Silent send logic
- Platform-specific defaults

## Adding New Tests

When adding new tests:

1. Create a new test class in `Tests/BugSplatTests/`
2. Import the class being tested
3. Use XCTest assertions
4. Add the file to the test target in Xcode

Example:
```objc
#import <XCTest/XCTest.h>
#import "ClassToTest.h"

@interface ClassToTestTests : XCTestCase
@end

@implementation ClassToTestTests

- (void)testSomething
{
    XCTAssertTrue(YES);
}

@end
```

## Mock Objects

The test suite includes mock implementations for dependency injection:

- `MockURLSession`: Intercepts and records network requests
- `MockCrashReporter`: Simulates PLCrashReporter behavior
- `MockCrashStorage`: In-memory file storage
- `MockUserDefaults`: In-memory user defaults
- `MockBundle`: Configurable Info.plist values

These mocks allow testing BugSplat components in isolation without:
- Making real network requests
- Writing to the file system
- Interfering with NSUserDefaults
- Requiring a running crash reporter
