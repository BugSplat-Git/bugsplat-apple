//
//  BugSplatTest-SwiftUIApp.swift
//  BugSplatTest-SwiftUI
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI
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

    /// Orphaned session logs older than this are pruned at launch (7 days).
    /// Sessions that end normally never trigger a delegate cleanup callback,
    /// so their logs must be aged out here instead.
    private static let sessionLogMaxAge: TimeInterval = 7 * 24 * 60 * 60

    override init() {
        super.init()

        // Initialize BugSplat
        let bugSplat = BugSplat.shared()
        bugSplat.delegate = self
        // Enable user prompt for crash reports (default is true for silent reporting)
        // When set to false, users see Send/Don't Send/Always Send options
        bugSplat.autoSubmitCrashReport = false

        // example of programmatically setting user meta data
        // when user has granted permission to include their PII in a crash report
        bugSplat.userName = "Foo Barr"
        bugSplat.userEmail = "foo@barr.com"

        // Optionally, add some attributes to your crash reports.
        // Attributes are artibrary key/value pairs that are searchable in the BugSplat dashboard.
        bugSplat.set("Value of Plain Attribute", for: "PlainAttribute")
        bugSplat.set("Value of not so plain <value> Attribute", for: "NotSoPlainAttribute")
        bugSplat.set("Launch Date <![CDATA[\(Date.now)]]> Value", for: "CDATAExample")
        bugSplat.set("<!-- 'value is > or < before' --> \(Date.now)", for: "CommentExample")
        bugSplat.set("This value will get XML escaping because of 'this' and & and < and >", for: "EscapingExample")

        // Opt in to fatal hang detection. When the main thread is blocked past the built-in
        // threshold and the app is subsequently terminated without recovering, a hang report
        // is uploaded on the next launch using the same pipeline as crash reports.
        bugSplat.enableHangDetection = true

        // Don't forget to call start after you've finished configuring BugSplat
        bugSplat.start()

        // BugSplat generates a unique sessionID every launch and embeds it into any
        // crash report captured during this session. Naming this session's log file
        // after the sessionID is what makes the log recoverable: crashes are processed
        // at the NEXT launch, and the delegate callbacks receive the *crashed* session's
        // ID, so the matching `<sessionID>.log` file can be read back. A fixed log path
        // would already be overwritten by the new launch before the report is sent.
        createSessionLogFile(for: bugSplat.sessionID)

        // Clean up logs left behind by sessions that ended normally (no crash means
        // no delegate callback ever asks for or deletes them).
        pruneOrphanedSessionLogs(currentSessionID: bugSplat.sessionID)
    }

    // MARK: - Per-Session Log Files

    /// Directory containing one log file per app session: <Application Support>/SessionLogs/
    private var sessionLogsDirectoryURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SessionLogs", isDirectory: true)
    }

    /// The log file for a given session: SessionLogs/<sessionID>.log
    /// The file name IS the mapping from session ID to log file — no separate
    /// bookkeeping (database, plist, etc.) is needed to find a session's log later.
    private func sessionLogFileURL(for sessionID: UUID) -> URL? {
        sessionLogsDirectoryURL?.appendingPathComponent("\(sessionID.uuidString).log")
    }

    /// Creates this session's log file and seeds it with a few sample entries.
    /// In a real app, append log entries to this file throughout the session;
    /// if the app crashes, `attachment(for:sessionID:)` reads this exact file
    /// back at the next launch and attaches it to the crash report.
    private func createSessionLogFile(for sessionID: UUID) {
        let fileManager = FileManager.default
        guard let fileURL = sessionLogFileURL(for: sessionID) else {
            print("Could not access Application Support directory")
            return
        }

        let logContent = """
        =====================================
        BugSplat Per-Session Log File
        =====================================
        Session ID: \(sessionID.uuidString)
        App Launch: \(Date())
        Device: \(UIDevice.current.model)
        System Version: \(UIDevice.current.systemVersion)

        This log file is named after BugSplat's per-launch sessionID. If this
        session crashes, the crash report embeds the sessionID, and at the next
        launch the BugSplatDelegate is handed that same ID — so this exact file
        (not the new session's log) is attached to the crash report.

        Log entries:
        [\(Date())] INFO: Application started
        [\(Date())] DEBUG: BugSplat initialized
        [\(Date())] INFO: Session log created for session \(sessionID.uuidString)
        =====================================
        """

        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try logContent.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Session log created at: \(fileURL.path)")
        } catch {
            print("Failed to create session log: \(error)")
        }
    }

    /// Removes session logs older than 7 days, except the current session's log.
    /// Sessions that end normally never receive `bugSplatDidFinishSendingCrashReport`,
    /// so their logs are never deleted by the delegate — without pruning they would
    /// accumulate forever. 7 days comfortably outlives any pending crash report
    /// waiting to be sent on a future launch.
    private func pruneOrphanedSessionLogs(currentSessionID: UUID) {
        let fileManager = FileManager.default
        guard let directoryURL = sessionLogsDirectoryURL,
              let logFiles = try? fileManager.contentsOfDirectory(at: directoryURL,
                                                                  includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let cutoffDate = Date().addingTimeInterval(-Self.sessionLogMaxAge)
        for fileURL in logFiles {
            // Never delete the current session's log — it's needed if this session crashes.
            guard fileURL.lastPathComponent != "\(currentSessionID.uuidString).log" else { continue }
            guard let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  creationDate < cutoffDate else { continue }
            try? fileManager.removeItem(at: fileURL)
            print("Pruned orphaned session log: \(fileURL.lastPathComponent)")
        }
    }

    // MARK: BugSplatDelegate
    func bugSplatWillSendCrashReport(_ bugSplat: BugSplat, sessionID: UUID?) {
        print("\(#file) - \(#function) - sessionID: \(sessionID?.uuidString ?? "nil")")
    }

    func bugSplatWillSendCrashReportsAlways(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    /// The crash report (and its attached session log) was delivered, so the
    /// crashed session's log is no longer needed — delete it. This is invoked
    /// once per report, so cleanup stays correct even when several queued
    /// reports upload during a single launch.
    func bugSplatDidFinishSendingCrashReport(_ bugSplat: BugSplat, sessionID: UUID?) {
        print("\(#file) - \(#function) - sessionID: \(sessionID?.uuidString ?? "nil")")

        guard let sessionID, let fileURL = sessionLogFileURL(for: sessionID) else { return }
        try? FileManager.default.removeItem(at: fileURL)
        print("Deleted session log for delivered crash report: \(fileURL.lastPathComponent)")
    }

    func bugSplatWillCancelSendingCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillShowSubmitCrashReportAlert(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    /// The upload failed — deliberately keep the session log. BugSplat retries
    /// the upload on a future launch and will ask for the attachment again.
    func bugSplat(_ bugSplat: BugSplat, didFailWithError error: Error, sessionID: UUID?) {
        print("\(#file) - \(#function) - sessionID: \(sessionID?.uuidString ?? "nil") - error: \(error)")
    }

    /// Returns the crashed session's log file as a crash report attachment.
    /// `sessionID` identifies the session that CRASHED — not the current one.
    /// Because each session's log is named `<sessionID>.log`, the exact log from
    /// the crashed session can be read back here, even though the crash report
    /// is processed one launch later.
    func attachment(for bugSplat: BugSplat, sessionID: UUID?) -> BugSplatAttachment? {
        guard let sessionID,
              let fileURL = sessionLogFileURL(for: sessionID),
              let logData = try? Data(contentsOf: fileURL) else {
            // sessionID is nil when the report was recorded by an SDK version that
            // predates session tracking, and the log file may have been pruned.
            // A real app could fall back to a heuristic here (e.g. attach its most
            // recent log file); this demo simply attaches nothing.
            print("No session log available for crashed session: \(sessionID?.uuidString ?? "nil")")
            return nil
        }

        print("Attaching log for crashed session: \(sessionID.uuidString)")
        return BugSplatAttachment(
            filename: "session.log",
            attachmentData: logData,
            contentType: "text/plain"
        )
    }
}
