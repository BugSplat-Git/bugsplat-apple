import XCTest
@testable import BugSplat

private struct FakeInfo: InfoDictionaryProviding {
    var values: [String: Any]
    func object(forInfoDictionaryKey key: String) -> Any? { values[key] }
}

final class BundleInfoTests: XCTestCase {
    func testExplicitValuesWin() throws {
        let info = FakeInfo(values: ["BugSplatDatabase": "plist", "CFBundleName": "PlistApp", "CFBundleShortVersionString": "0.1"])
        let r = try BundleInfo.resolve(database: "fred", application: "MyApp", version: "9.0.0", from: info)
        XCTAssertEqual(r, .init(database: "fred", application: "MyApp", version: "9.0.0"))
    }

    func testInfoPlistDefaults() throws {
        let info = FakeInfo(values: [
            "BugSplatDatabase": "fred",
            "CFBundleDisplayName": "My App",
            "CFBundleName": "MyApp",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "456",
        ])
        let r = try BundleInfo.resolve(database: nil, application: nil, version: nil, from: info)
        XCTAssertEqual(r.database, "fred")
        XCTAssertEqual(r.application, "My App", "display name beats bundle name")
        XCTAssertEqual(r.version, "1.2.3 (456)", "build number is appended when it differs")
    }

    func testVersionWithoutBuildNumber() throws {
        let info = FakeInfo(values: ["BugSplatDatabase": "fred", "CFBundleName": "MyApp", "CFBundleShortVersionString": "2.0", "CFBundleVersion": "2.0"])
        XCTAssertEqual(try BundleInfo.resolve(database: nil, application: nil, version: nil, from: info).version, "2.0")
    }

    func testMissingDatabaseIsInvalidArgument() {
        let info = FakeInfo(values: ["CFBundleName": "MyApp", "CFBundleShortVersionString": "1.0"])
        XCTAssertThrowsError(try BundleInfo.resolve(database: nil, application: nil, version: nil, from: info)) { error in
            XCTAssertEqual((error as? BugSplatError)?.code, .invalidArgument)
        }
        XCTAssertThrowsError(try BundleInfo.resolve(database: "   ", application: nil, version: nil, from: info))
    }

    func testMissingVersionIsInvalidArgument() {
        let info = FakeInfo(values: ["BugSplatDatabase": "fred", "CFBundleName": "MyApp"])
        XCTAssertThrowsError(try BundleInfo.resolve(database: nil, application: nil, version: nil, from: info))
    }
}
