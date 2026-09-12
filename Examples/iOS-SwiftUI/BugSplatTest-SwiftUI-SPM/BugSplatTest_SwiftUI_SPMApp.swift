//
//  BugSplatTest_SwiftUI_SPMApp.swift
//  BugSplatTest-SwiftUI-SPM
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI
import BugSplat

@main
struct BugSplatTest_SwiftUI_SPMApp: App {
    @StateObject private var activity = Activity()

    init() {
        var options = BugSplat.Options()
        options.uploadPolicy = .dialog                       // ask at the next launch (Send / Don't Send / Always Send)
        options.hangDetection = .init(timeout: 3, policy: .report)
        options.attributes = ["sample": "iOS-SwiftUI"]
        options.logHandler = { level, line in print("[bugsplat \(level)] \(line)") }
        do {
            try BugSplat.start(options: options)             // BugSplatDatabase, name and version from Info.plist
            BugSplat.user = "Foo Barr"
            BugSplat.email = "foo@barr.com"
            BugSplat.key = "en-US"
            print("BugSplat \(BugSplat.sdkVersion) started; environment: \(BugSplat.environment ?? "?")")
        } catch {
            print("BugSplat.start failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(activity)
                .onAppear { BugSplat.delegate = activity }
        }
    }
}

/// Listens to the SDK and keeps a log the UI shows.
final class Activity: ObservableObject, BugSplatDelegate {
    @Published var lines: [String] = []

    func log(_ line: String) {
        DispatchQueue.main.async { self.lines.append(line) }
    }

    func bugSplatWillShowReportPrompt(reportCount count: Int) { log("prompting for \(count) report(s) from the last session") }
    func bugSplatDidCancelSendingReports() { log("user chose Don't Send") }
    func bugSplatWillSendReportsAlways() { log("user chose Always Send") }
    func bugSplatDidSendReport(crashId: Int64, infoURL: URL?, folder: URL) { log("sent report \(crashId) \(infoURL?.absoluteString ?? "")") }
    func bugSplatDidFailToSendReport(_ error: Error, folder: URL) { log("upload failed: \(error)") }
}
