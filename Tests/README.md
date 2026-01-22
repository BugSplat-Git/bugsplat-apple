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

## Running Tests

### From Xcode

1. Open `BugSplat.xcworkspace` in Xcode
2. Select the `BugSplatMacTests` or `BugSplatIOSTests` scheme
3. Press `Cmd+U` to run tests, or use Product → Test

### From Command Line

```bash
# Run macOS tests
xcodebuild test -workspace BugSplat.xcworkspace -scheme BugSplatMacTests -destination 'platform=macOS'

# Run iOS tests
xcodebuild test -workspace BugSplat.xcworkspace -scheme BugSplatIOSTests -destination 'platform=iOS Simulator,name=iPhone 16'
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
4. Add the `.m` file to both test targets (`BugSplatMacTests` and `BugSplatIOSTests`) in Xcode

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
