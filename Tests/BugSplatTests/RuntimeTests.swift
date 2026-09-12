import XCTest
@testable import BugSplat

/// End to end against the real native runtime: start -> BugSplatMonitor -> capture -> import ->
/// pending -> upload to `fred`. Runs only with `BUGSPLAT_RUNTIME_TESTS=1` (network, a few
/// seconds, one process-wide session) and prints the crash id it produced.
final class RuntimeTests: XCTestCase {
    static let enabled = ProcessInfo.processInfo.environment["BUGSPLAT_RUNTIME_TESTS"] == "1"
    static let database = ProcessInfo.processInfo.environment["BUGSPLAT_DATABASE"] ?? "fred"

    func testCaptureImportAndUpload() async throws {
        try XCTSkipUnless(Self.enabled, "set BUGSPLAT_RUNTIME_TESTS=1")
        try XCTSkipIf(BugSplat.isStarted, "another test already started the session")

        let root = ProcessInfo.processInfo.environment["BUGSPLAT_TEST_STORE_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let store = root.appendingPathComponent("bugsplat-runtime-\(UUID().uuidString)")
        let attachment = store.appendingPathComponent("session.log")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try "hello from the runtime test\n".write(to: attachment, atomically: true, encoding: .utf8)

        let log = LogSink()
        var o = BugSplat.Options()
        o.uploadPolicy = .manual       // the app drains: no dialog, no reporter involvement
        o.storeDirectory = store
        o.openSupportURL = false
        o.attributes = ["suite": "RuntimeTests"]
        o.logHandler = { _, line in log.append(line) }

        try BugSplat.start(database: Self.database, application: "BugSplatAppleRuntimeTest", version: BugSplat.sdkVersion, options: o)
        XCTAssertTrue(BugSplat.isStarted)
        XCTAssertTrue(BugSplat.hasCapability(.outOfProcess), "macOS capture is out of process")
        let environment = try XCTUnwrap(BugSplat.environment)
        XCTAssertTrue(environment.hasPrefix("macOS"), environment)

        BugSplat.user = "runtime@bugsplat.com"
        BugSplat.email = "runtime@bugsplat.com"
        BugSplat.userDescription = "captureReport from XCTest"
        try BugSplat.setAttribute("branch", value: "feat/9.0-bugsplat-native")
        try BugSplat.addAttachment(attachment)
        XCTAssertEqual(BugSplat.attributes["branch"], "feat/9.0-bugsplat-native")
        XCTAssertEqual(BugSplat.attachments, [attachment])

        // Dump the live process; the monitor writes the minidump, imports it into the store and,
        // because the policy is manual, leaves it pending for us.
        try BugSplat.captureReport()

        var pending: [PendingReport] = []
        for _ in 0..<60 where pending.isEmpty {
            try await Task.sleep(nanoseconds: 500_000_000)
            pending = BugSplat.pendingReports()
        }
        let report = try XCTUnwrap(pending.first, "monitor did not import the capture within 30 s; log: \(log.tail(20))")
        XCTAssertEqual(report.kind, .capture)
        XCTAssertEqual(report.database, Self.database)
        XCTAssertEqual(report.application, "BugSplatAppleRuntimeTest")
        XCTAssertEqual(report.environment, environment)
        XCTAssertEqual(report.attributes["branch"], "feat/9.0-bugsplat-native")
        XCTAssertEqual(report.attributes["suite"], "RuntimeTests")
        XCTAssertTrue(report.attachments.contains("session.log"), "\(report.attachments)")
        XCTAssertEqual(report.uploadPolicy, "manual")
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.folder.appendingPathComponent("BugSplatCrashData.json").path))

        let result = try await BugSplat.send(report, description: "sent by RuntimeTests")
        XCTAssertGreaterThan(result.crashId, 0)
        XCTAssertEqual(result.httpStatus, 200)
        print("BUGSPLAT_RUNTIME_CRASH_ID=\(result.crashId) infoURL=\(result.infoURL?.absoluteString ?? "-")")
        XCTAssertTrue(BugSplat.pendingReports().isEmpty, "uploaded folders are removed from the store")

        // Feedback goes through the same uploader from inside the process.
        let feedback = try await BugSplat.postFeedback(title: "RuntimeTests feedback", description: "posted by the Swift SDK", attachments: [attachment])
        XCTAssertTrue(feedback.isDeferred, "manual policy leaves feedback pending")
        let pendingFeedback = try XCTUnwrap(BugSplat.pendingReports().first { $0.kind == .feedback })
        let sent = try await BugSplat.send(pendingFeedback)
        XCTAssertGreaterThan(sent.crashId, 0)
        print("BUGSPLAT_RUNTIME_FEEDBACK_ID=\(sent.crashId)")

        // A caught error as a structured report.
        struct Boom: Error {}
        let structured = try await BugSplat.post(Boom())
        XCTAssertTrue(structured.isDeferred)
        let pendingStructured = try XCTUnwrap(BugSplat.pendingReports().first { $0.kind == .structured })
        let sentStructured = try await BugSplat.send(pendingStructured)
        XCTAssertGreaterThan(sentStructured.crashId, 0)
        print("BUGSPLAT_RUNTIME_STRUCTURED_ID=\(sentStructured.crashId)")

        for leftover in BugSplat.pendingReports() { try BugSplat.discard(leftover) }
    }
}

/// The SDK logs from its own threads; collect the lines under a lock.
private final class LogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock(); lines.append(line); lock.unlock()
    }

    func tail(_ n: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.suffix(n).joined(separator: "\n")
    }
}
