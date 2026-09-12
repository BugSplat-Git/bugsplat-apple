import XCTest
import BugSplatNative
@testable import BugSplat

final class OptionsTests: XCTestCase {
    func testDefaults() {
        let o = BugSplat.Options()
        XCTAssertEqual(o.uploadPolicy, .dialog)
        XCTAssertEqual(o.dumpType, .normal)
        XCTAssertNil(o.hangDetection)
        XCTAssertNil(o.storeDirectory)
        XCTAssertNil(o.openSupportURL)
        XCTAssertTrue(o.crashSignature)
        XCTAssertFalse(o.chainPreviousHandlers)
        XCTAssertTrue(o.promptForPendingReports)
        XCTAssertEqual(o.attributes, [:])
        XCTAssertEqual(o.attachments, [])
    }

    func testNativeOptionsRoundTripDoesNotCrash() {
        var o = BugSplat.Options()
        o.uploadPolicy = .quiet
        o.dumpType = .heap
        o.hangDetection = .init(timeout: 2.5, policy: .reportAndTerminate)
        o.storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-options-test")
        o.themeDirectory = URL(fileURLWithPath: "/tmp/theme")
        o.openSupportURL = false
        o.crashTypeId = 5
        o.key = "k"; o.user = "u"; o.email = "e"; o.userDescription = "d"; o.notes = "n"; o.environment = "env"
        o.attributes = ["a": "1", "b": "2"]
        o.attachments = [URL(fileURLWithPath: "/tmp/a.log")]
        o.logHandler = { _, _ in }
        let native = o.makeNative(database: "fred", application: "App", version: "1.0")
        XCTAssertNotNil(native)
        bugsplat_options_free(native)
    }

    func testConfigurationBridgesToOptions() {
        let c = BugSplatConfiguration()
        c.uploadPolicy = .manual
        c.hangTimeout = 3
        c.hangPolicy = .reportAndTerminate
        c.openSupportURL = NSNumber(value: false)
        c.crashTypeId = 21
        c.attributes = ["x": "y"]
        let o = c.options
        XCTAssertEqual(o.uploadPolicy, .manual)
        XCTAssertEqual(o.hangDetection, .init(timeout: 3, policy: .reportAndTerminate))
        XCTAssertEqual(o.openSupportURL, false)
        XCTAssertEqual(o.crashTypeId, 21)
        XCTAssertEqual(o.attributes, ["x": "y"])

        let none = BugSplatConfiguration().options
        XCTAssertNil(none.hangDetection)
        XCTAssertNil(none.openSupportURL)
        XCTAssertNil(none.crashTypeId)
    }

    func testEnumsMatchTheABI() {
        XCTAssertEqual(UploadPolicy.dialog.rawValue, Int(BUGSPLAT_UPLOAD_DIALOG.rawValue))
        XCTAssertEqual(UploadPolicy.quiet.rawValue, Int(BUGSPLAT_UPLOAD_QUIET.rawValue))
        XCTAssertEqual(UploadPolicy.manual.rawValue, Int(BUGSPLAT_UPLOAD_MANUAL.rawValue))
        XCTAssertEqual(DumpType.full.rawValue, Int(BUGSPLAT_DUMP_FULL.rawValue))
        XCTAssertEqual(HangPolicy.reportAndTerminate.rawValue, Int(BUGSPLAT_HANG_REPORT_AND_TERMINATE.rawValue))
        XCTAssertEqual(ReportFormat.json.rawValue, Int(BUGSPLAT_REPORT_JSON.rawValue))
        XCTAssertEqual(Capability.crashSignature.rawValue, Int(BUGSPLAT_CAP_CRASH_SIGNATURE.rawValue))
        XCTAssertEqual(LogLevel.error.rawValue, Int(BUGSPLAT_LOG_ERROR.rawValue))
    }

    func testVersionAndAbi() {
        XCTAssertTrue(BugSplat.sdkVersion.hasPrefix("9."), BugSplat.sdkVersion)
        XCTAssertEqual(bugsplat_abi_version(), 1)
    }

    func testBeforeStart() {
        guard !BugSplat.isStarted else { return }
        XCTAssertNil(BugSplat.environment)
        XCTAssertNil(BugSplat.logFileURL)
        XCTAssertEqual(BugSplat.pendingReports(), [])
        XCTAssertThrowsError(try BugSplat.captureReport()) { XCTAssertEqual(($0 as? BugSplatError)?.code, .notStarted) }
        XCTAssertThrowsError(try BugSplat.setAttribute("a", value: "b")) { XCTAssertEqual(($0 as? BugSplatError)?.code, .notStarted) }
        XCTAssertThrowsError(try BugSplat.watchThread(name: "x")) { XCTAssertEqual(($0 as? BugSplatError)?.code, .notStarted) }
        XCTAssertFalse(BugSplat.hasCapability(.outOfProcess))
    }

    func testStartWithoutMonitorFailsLoudly() {
        // The OOP rule: a missing BugSplatMonitor is an init error, never a silent fallback.
        guard !BugSplat.isStarted else { return }
        var o = BugSplat.Options()
        o.monitorURL = URL(fileURLWithPath: "/nonexistent/BugSplatMonitor")
        o.storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-no-monitor")
        XCTAssertThrowsError(try BugSplat.start(database: "fred", application: "NoMonitor", version: "1.0", options: o)) { error in
            XCTAssertEqual((error as? BugSplatError)?.code, .monitorNotFound)
        }
        XCTAssertFalse(BugSplat.isStarted)
    }
}
