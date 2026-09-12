// swift run HelloCrash [crash|capture|feedback|error|hang] [quiet|manual]
//
// Capture, the dialog and the upload happen out of process (BugSplatMonitor and
// BugSplatReporter.app inside BugSplatNative.framework); this program only describes the report.
import Foundation
import BugSplat

let args = CommandLine.arguments.dropFirst()
let mode = args.first ?? "crash"

var options = BugSplat.Options()
options.uploadPolicy = args.contains("quiet") ? .quiet : args.contains("manual") ? .manual : .dialog
options.hangDetection = .init(timeout: 3, policy: .report)
options.attributes = ["sample": "HelloCrash-macOS", "mode": mode]
options.logHandler = { level, line in print("[bugsplat \(level)] \(line)") }

do {
    try BugSplat.start(database: "fred", application: "HelloCrash-macOS", version: "1.0.0", options: options)
} catch {
    print("BugSplat.start failed: \(error)")
    print("BugSplatNative.framework must be embedded with its Helpers (BugSplatMonitor, BugSplatReporter.app).")
    exit(1)
}

BugSplat.user = "fred@bugsplat.com"
BugSplat.userDescription = "running the \(mode) sample"
print("BugSplat \(BugSplat.sdkVersion) started; environment: \(BugSplat.environment ?? "?")")
print("store: \(BugSplat.storeDirectory?.path ?? "?")")

let log = FileManager.default.temporaryDirectory.appendingPathComponent("hello-crash.log")
try? "hello from HelloCrash\n".write(to: log, atomically: true, encoding: .utf8)
try? BugSplat.addAttachment(log)   // attachments can change at any time

switch mode {
case "capture":
    try BugSplat.captureReport()
    print("captured a report of the live process; waiting for the monitor to import it")
    sleep(5)
    for report in BugSplat.pendingReports() {
        print("pending \(report.kind) report \(report.id) in \(report.folder.path)")
        if options.uploadPolicy == .manual {
            let result = try BugSplat.sendSync(report)
            print("uploaded as crash \(result.crashId) \(result.infoURL?.absoluteString ?? "")")
        }
    }
case "feedback":
    let result = try BugSplat.postFeedbackSync(title: "Feedback from HelloCrash", description: "The Swift sample says hi", attachments: [log])
    print(result.isDeferred ? "feedback left pending (manual policy)" : "feedback report \(result.crashId) \(result.infoURL?.absoluteString ?? "")")
case "error":
    struct Boom: Error {}
    let result = try BugSplat.Report(error: Boom()).postSync()
    print(result.isDeferred ? "error report left pending (manual policy)" : "error report \(result.crashId)")
case "hang":
    print("blocking the main thread for 6 s; the watchdog reports a hang after 3 s and the app keeps running")
    Thread.sleep(forTimeInterval: 6)
    sleep(3)
default:
    print("crashing now; the dialog appears, the report uploads, the support URL opens")
    let p = UnsafeMutablePointer<Int>(bitPattern: 0x10)!
    p.pointee = 42
}
