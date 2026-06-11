//
//  AppDelegate.swift
//  BugSplatTest-UIKit-Swift
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import UIKit
import BugSplat

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// How long a session log is kept before being pruned at startup.
    /// Sessions that end normally never receive `bugSplatDidFinishSendingCrashReport(_:sessionID:)`,
    /// so their logs must eventually be cleaned up some other way.
    private static let sessionLogMaxAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        // Initialize BugSplat
        let bugSplat = BugSplat.shared()
        bugSplat.delegate = self
        // Enable user prompt for crash reports (default is true for silent reporting)
        // When set to false, users see Send/Don't Send/Always Send options
        bugSplat.autoSubmitCrashReport = false

        // Optionally, add some attributes to your crash reports.
        // Attributes are artibrary key/value pairs that are searchable in the BugSplat dashboard.
        bugSplat.set("Value of Plain Attribute", for: "PlainAttribute")
        bugSplat.set("Value of not so plain <value> Attribute", for: "NotSoPlainAttribute")
        bugSplat.set("Launch Date <![CDATA[\(Date.now)]]> Value", for: "CDATAExample")
        bugSplat.set("<!-- 'value is > or < before' --> \(Date.now)", for: "CommentExample")
        bugSplat.set("This value will get XML escaping because of 'this' and & and < and >", for: "EscapingExample")

        // Opt in to fatal hang detection.
        bugSplat.enableHangDetection = true

        // Don't forget to call start after you've finished configuring BugSplat
        bugSplat.start()

        // Create this session's log file, named after BugSplat's per-launch sessionID.
        //
        // WHY per-session file naming matters: crash reports are processed at the NEXT
        // launch of the app, after a brand new session (with a new sessionID and a new
        // log file) has already begun. A single fixed log path that gets overwritten
        // every launch would no longer contain the crashed session's log by the time
        // the SDK asks for an attachment. By naming each log file after its sessionID,
        // the file name itself records the session-to-log mapping, and the crashed
        // session's log can be looked up exactly via the sessionID the SDK passes to
        // the delegate callbacks below.
        createSessionLogFile(for: bugSplat.sessionID)

        // Prune session logs from sessions that ended long ago. Sessions that exit
        // normally never crash, so their logs are never cleaned up by the delegate
        // callbacks — without pruning they would accumulate forever.
        pruneStaleSessionLogs(currentSessionID: bugSplat.sessionID)

        return true
    }

    // MARK: - Per-Session Log Files

    /// Directory holding one log file per app session: <Application Support>/SessionLogs/<sessionID>.log
    private var sessionLogsDirectoryURL: URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("Could not access Application Support directory")
            return nil
        }
        return appSupportURL.appendingPathComponent("SessionLogs", isDirectory: true)
    }

    /// Returns the log file URL for a given session ID.
    /// The file NAME is the session-to-log mapping — no extra bookkeeping required.
    private func logFileURL(for sessionID: UUID) -> URL? {
        return sessionLogsDirectoryURL?.appendingPathComponent("\(sessionID.uuidString).log")
    }

    /// Creates this session's log file and writes a few sample log lines to it.
    /// In a real app, you would route your logging framework's output to this file
    /// and append to it throughout the session.
    private func createSessionLogFile(for sessionID: UUID) {
        guard let directoryURL = sessionLogsDirectoryURL,
              let logFileURL = logFileURL(for: sessionID) else {
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

        This log file is named after BugSplat's per-launch sessionID.
        If this session crashes, the crash report is processed at the
        NEXT launch, and the SDK passes this session's ID back to the
        BugSplatDelegate so exactly this file can be attached.

        Log entries:
        [\(Date())] INFO: Application started
        [\(Date())] DEBUG: BugSplat initialized
        [\(Date())] INFO: Session log file created for session \(sessionID.uuidString)
        =====================================
        """

        do {
            // Create the SessionLogs directory if it doesn't already exist
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try logContent.write(to: logFileURL, atomically: true, encoding: .utf8)
            print("Session log file created at: \(logFileURL.path)")
        } catch {
            print("Failed to create session log file: \(error)")
        }
    }

    /// Deletes session logs older than `sessionLogMaxAge`, never touching the current
    /// session's log. Sessions that end normally never get a
    /// `bugSplatDidFinishSendingCrashReport(_:sessionID:)` callback (there is no crash
    /// report to send), so this startup sweep is what keeps the directory bounded.
    private func pruneStaleSessionLogs(currentSessionID: UUID) {
        guard let directoryURL = sessionLogsDirectoryURL else { return }

        let fileManager = FileManager.default
        guard let logURLs = try? fileManager.contentsOfDirectory(at: directoryURL,
                                                                 includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return  // Directory doesn't exist yet — nothing to prune
        }

        let cutoffDate = Date().addingTimeInterval(-Self.sessionLogMaxAge)
        let currentLogFilename = "\(currentSessionID.uuidString).log"

        for logURL in logURLs {
            // Never delete the log for the session that is running right now
            guard logURL.lastPathComponent != currentLogFilename else { continue }

            guard let modificationDate = try? logURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modificationDate < cutoffDate else { continue }

            do {
                try fileManager.removeItem(at: logURL)
                print("Pruned stale session log: \(logURL.lastPathComponent)")
            } catch {
                print("Failed to prune session log \(logURL.lastPathComponent): \(error)")
            }
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

extension AppDelegate: BugSplatDelegate {


    // MARK: BugSplatDelegate

    /// The sessionID is the ID of the session that CRASHED (a previous launch),
    /// not the current session — when implemented, this is called instead of
    /// the legacy `bugSplatWillSendCrashReport(_:)`.
    func bugSplatWillSendCrashReport(_ bugSplat: BugSplat, sessionID: UUID?) {
        print("\(#file) - \(#function) sessionID: \(sessionID?.uuidString ?? "nil")")
    }

    func bugSplatWillSendCrashReportsAlways(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    /// The crash report for the given session was delivered, so its log file is no
    /// longer needed — delete it. This is invoked once per report, so when several
    /// queued reports upload in a single launch, each crashed session's log is
    /// cleaned up individually and correctly.
    func bugSplatDidFinishSendingCrashReport(_ bugSplat: BugSplat, sessionID: UUID?) {
        print("\(#file) - \(#function) sessionID: \(sessionID?.uuidString ?? "nil")")

        guard let sessionID = sessionID, let logFileURL = logFileURL(for: sessionID) else { return }

        do {
            try FileManager.default.removeItem(at: logFileURL)
            print("Deleted delivered session log: \(logFileURL.lastPathComponent)")
        } catch {
            print("Failed to delete session log \(logFileURL.lastPathComponent): \(error)")
        }
    }

    func bugSplatWillCancelSendingCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillShowSubmitCrashReportAlert(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    /// Sending the crash report failed. Deliberately KEEP the session's log file —
    /// the SDK will retry the upload on a future launch and will ask for the
    /// attachment again via `attachment(for:sessionID:)`.
    func bugSplat(_ bugSplat: BugSplat, didFailWithError error: Error, sessionID: UUID?) {
        print("\(#file) - \(#function) sessionID: \(sessionID?.uuidString ?? "nil")")
    }

    /// Returns the crashed session's log file as an attachment for the crash report.
    /// The sessionID identifies which previous session crashed, and because each
    /// session's log is named `<sessionID>.log`, looking up the right file is just
    /// a path construction — this is the payoff of per-session file naming.
    func attachment(for bugSplat: BugSplat, sessionID: UUID?) -> BugSplatAttachment? {
        // sessionID is nil for crash reports recorded by older SDK versions that
        // predate session tracking. A real app could fall back to a heuristic here
        // (e.g. attach the most recent log that isn't the current session's).
        guard let sessionID = sessionID else {
            print("No sessionID for crash report — no session log attached")
            return nil
        }

        guard let logFileURL = logFileURL(for: sessionID),
              let logData = try? Data(contentsOf: logFileURL) else {
            // The crashed session's log is missing (e.g. already pruned)
            print("Could not read session log for session \(sessionID.uuidString)")
            return nil
        }

        print("Attaching session log to crash report: \(logFileURL.lastPathComponent)")
        return BugSplatAttachment(
            filename: "session.log",
            attachmentData: logData,
            contentType: "text/plain"
        )
    }
}
