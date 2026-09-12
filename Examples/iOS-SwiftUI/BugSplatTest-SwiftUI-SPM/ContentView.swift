//
//  ContentView.swift
//  BugSplatTest-SwiftUI-SPM
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI
import BugSplat

struct ContentView: View {
    @EnvironmentObject private var activity: Activity
    @State private var feature1 = false
    @State private var feature2 = false
    @State private var showFeedback = false
    @State private var pending: [PendingReport] = []

    let prop: Int? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Attributes (searchable in the dashboard)") {
                    Toggle("Feature 1", isOn: $feature1)
                    Toggle("Feature 2", isOn: $feature2)
                }
                Section("Reports") {
                    Button("Crash") { _ = prop! }
                    Button("Capture a report of the live process") { run { try BugSplat.captureReport() } }
                    Button("Report a caught error") {
                        struct Boom: Error {}
                        Task { await report { try await BugSplat.post(Boom()) } }
                    }
                    Button("Hang the main thread for 6 s") { Thread.sleep(forTimeInterval: 6) }
                    Button("Send feedback") { showFeedback = true }
                }
                Section("Pending reports (\(pending.count))") {
                    ForEach(pending) { report in
                        VStack(alignment: .leading) {
                            Text("\(report.kind.rawValue) \(report.crashTime.map { $0.formatted() } ?? "")")
                            Text(report.id).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Send") { Task { await report { try await BugSplat.send(report) } } }
                            Button("Discard", role: .destructive) { run { try BugSplat.discard(report) } }
                        }
                    }
                    Button("Refresh") { pending = BugSplat.pendingReports() }
                }
                Section("Activity") {
                    ForEach(Array(activity.lines.enumerated()), id: \.offset) { Text($0.element).font(.caption) }
                }
            }
            .navigationTitle("BugSplat \(BugSplat.sdkVersion)")
        }
        .onChange(of: feature1) { _, on in run { try BugSplat.setAttribute("Feature1", value: on.description) } }
        .onChange(of: feature2) { _, on in run { try BugSplat.setAttribute("Feature2", value: on.description) } }
        .onAppear { pending = BugSplat.pendingReports() }
        .sheet(isPresented: $showFeedback) { FeedbackSheet() }
    }

    private func run(_ body: () throws -> Void) {
        do { try body(); activity.log("ok") } catch { activity.log("error: \(error)") }
    }

    private func report(_ body: () async throws -> UploadResult) async {
        do {
            let r = try await body()
            activity.log(r.isDeferred ? "report stored (manual policy)" : "report \(r.crashId) \(r.infoURL?.absoluteString ?? "")")
        } catch {
            activity.log("error: \(error)")
        }
        pending = BugSplat.pendingReports()
    }
}

#Preview {
    ContentView().environmentObject(Activity())
}
