import XCTest
@testable import BugSplat

final class PendingReportTests: XCTestCase {
    // A BugSplatCrashData.json (schema 2) as BugSplatMonitor writes it after importing a capture.
    static let sample = """
    {
      "schemaVersion": 2,
      "database": "fred",
      "appName": "HelloCrash",
      "appVersion": "1.0.0",
      "crashTypeId": "5",
      "key": "level-3",
      "user": "ada@example.com",
      "email": "ada@example.com",
      "userDescription": "clicked send",
      "notes": "",
      "environment": "macOS 15.2 (24C101) arm64",
      "attributes": { "branch": "main", "gpu": "M3" },
      "captureBackend": "crashpad",
      "reportKind": "hang",
      "dumpFile": "5d2f...dmp",
      "dumpType": "normal",
      "dumpFormat": "minidump",
      "attachments": ["hello.log", "later.log"],
      "crashTime": "2026-09-11T22:26:49Z",
      "signalOrExceptionCode": "SIGSEGV",
      "hangDurationMs": 6500,
      "uploadPolicy": "manual",
      "retryCount": 1,
      "ownerPid": 0,
      "processId": 4242
    }
    """

    func testParsesEveryField() throws {
        let report = try XCTUnwrap(PendingReport(folder: "/tmp/store/abc-123", json: Self.sample))
        XCTAssertEqual(report.id, "abc-123")
        XCTAssertEqual(report.folder.path, "/tmp/store/abc-123")
        XCTAssertEqual(report.kind, .hang)
        XCTAssertEqual(report.database, "fred")
        XCTAssertEqual(report.application, "HelloCrash")
        XCTAssertEqual(report.version, "1.0.0")
        XCTAssertEqual(report.environment, "macOS 15.2 (24C101) arm64")
        XCTAssertEqual(report.user, "ada@example.com")
        XCTAssertEqual(report.userDescription, "clicked send")
        XCTAssertEqual(report.signalOrExceptionCode, "SIGSEGV")
        XCTAssertEqual(report.hangDuration, 6.5)
        XCTAssertEqual(report.attributes, ["branch": "main", "gpu": "M3"])
        XCTAssertEqual(report.attachments, ["hello.log", "later.log"])
        XCTAssertEqual(report.uploadPolicy, "manual")
        XCTAssertEqual(report.retryCount, 1)
        let time = try XCTUnwrap(report.crashTime)
        XCTAssertEqual(Int(time.timeIntervalSince1970), 1789165609)
    }

    func testToleratesMissingAndWrongTypes() throws {
        let report = try XCTUnwrap(PendingReport(folder: "/tmp/x", json: #"{"database":"fred","retryCount":"three","hangDurationMs":"n/a"}"#))
        XCTAssertEqual(report.kind, .unknown)
        XCTAssertEqual(report.database, "fred")
        XCTAssertEqual(report.application, "")
        XCTAssertNil(report.environment)
        XCTAssertNil(report.hangDuration)
        XCTAssertNil(report.crashTime)
        XCTAssertEqual(report.retryCount, 0)
        XCTAssertEqual(report.attributes, [:])
    }

    func testNonObjectIsRejected() {
        XCTAssertNil(PendingReport(folder: "/tmp/x", json: "not json"))
        XCTAssertNil(PendingReport(folder: "/tmp/x", json: "[1,2]"))
    }
}
