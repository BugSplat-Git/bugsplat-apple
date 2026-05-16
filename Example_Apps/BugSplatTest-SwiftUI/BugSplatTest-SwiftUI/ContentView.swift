//
//  ContentView.swift
//  BugSplatTest-SwiftUI
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI
import UIKit
import BugSplat

struct ContentView: View {
    @State private var entries: [ActivityEntry] = ActivityLog.all()
    @State private var showFeedbackSheet = false
    @State private var showHangConfirm = false
    @State private var feedbackTitle = ""
    @State private var feedbackDescription = ""
    @State private var feedbackStatus: String?
    @Environment(\.scenePhase) private var scenePhase

    private var database: String {
        BugSplat.shared().bugSplatDatabase ?? "—"
    }

    private var sdkVersion: String {
        let v = Bundle(for: BugSplat.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(v ?? "—")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                titleRow.padding(.top, 22)
                Text("Trigger an event. We catch it, group it, route it to your dashboard.")
                    .font(.system(size: 15))
                    .foregroundColor(DemoColor.textSecondary)
                    .padding(.top, 6)

                sectionHeader("TRIGGER AN EVENT").padding(.top, 22)

                VStack(spacing: 12) {
                    EventCard(icon: "splat_crash",
                              title: "Crash",
                              subtitle: "Native crash · stack + threads + memory",
                              action: triggerCrash)
                    EventCard(icon: "splat_error",
                              title: "Non-Crash Error",
                              subtitle: "Exception caught · app keeps running",
                              action: triggerNonCrashError)
                    EventCard(icon: "splat_feedback",
                              title: "User Feedback",
                              subtitle: "Open the feedback sheet",
                              action: { showFeedbackSheet = true })
                    EventCard(icon: "splat_hang",
                              title: "Hang",
                              subtitle: "Freeze main thread · force-quit to upload",
                              action: { showHangConfirm = true })
                }
                .padding(.top, 12)

                recentActivityCard.padding(.top, 18)

                Text(feedbackStatus ?? "Shake the device to send feedback anytime.")
                    .font(.system(size: 13))
                    .foregroundColor(DemoColor.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(DemoColor.screenBg.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { entries = ActivityLog.all() }
        }
        .alert("Send Feedback", isPresented: $showFeedbackSheet) {
            TextField("Title", text: $feedbackTitle)
            TextField("Description", text: $feedbackDescription)
            Button("Send") { sendFeedback() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Simulate Fatal Hang?", isPresented: $showHangConfirm) {
            Button("Hang App", role: .destructive) { simulateHang() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The main thread will be blocked indefinitely. To produce an uploaded hang report you must force-quit the app while it's frozen (swipe up from the app switcher on device, or on the simulator run `xcrun simctl terminate booted com.bugsplat.BugSplatTest-SwiftUI`). On the next launch the report will upload. If you wait it out instead, no report will be sent — fatal-only by design.")
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack(spacing: 10) {
            Image("bugsplat_wordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 28)
            Spacer()
            Text(sdkVersion)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(DemoColor.textSecondary)
            StatusPill(connected: true)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("BugSplat SDK · Demo")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(DemoColor.textPrimary)
            DatabaseBadge(text: database)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(DemoColor.textTertiary)
    }

    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("RECENT ACTIVITY")
                Spacer()
                Button(action: openDashboard) {
                    Text("View dashboard ↗")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DemoColor.link)
                }
                .buttonStyle(.plain)
            }
            if entries.isEmpty {
                Text("No events yet — tap a card above to get started.")
                    .font(.system(size: 14))
                    .foregroundColor(DemoColor.textTertiary)
            } else {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        RecentActivityRow(entry: entry)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(DemoColor.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(DemoColor.cardStroke, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func triggerCrash() {
        // Record synchronously before the crash so the entry survives process death
        // and shows up when the app relaunches.
        ActivityLog.record(.crash, detail: "Native crash triggered")
        entries = ActivityLog.all()
        let prop: Int? = nil
        _ = prop!
    }

    private func triggerNonCrashError() {
        // Demo: pretend we caught an exception. Real apps would put a do/try/catch
        // around an actual risky operation and report the type name here.
        ActivityLog.record(.error, detail: "NSInvalidArgumentException caught")
        entries = ActivityLog.all()
    }

    private func simulateHang() {
        ActivityLog.record(.hang, detail: "Main thread frozen")
        entries = ActivityLog.all()
        // Block main indefinitely so the hang tracker persists a report and the
        // user can force-quit to produce a real fatal-hang upload on next launch.
        // Single sleep until distantFuture (~year 4001) - simpler than a spin
        // loop and keeps the CPU quiet while frozen.
        Thread.sleep(until: .distantFuture)
    }

    private func sendFeedback() {
        let title = feedbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Treat an empty title the same as Cancel - don't submit, don't record.
        guard !title.isEmpty else {
            feedbackTitle = ""
            feedbackDescription = ""
            return
        }
        feedbackStatus = "Sending..."
        BugSplat.shared().postFeedback(
            title: title,
            description: feedbackDescription.isEmpty ? nil : feedbackDescription,
            userName: nil,
            userEmail: nil,
            appKey: nil,
            attachments: nil
        ) { error in
            DispatchQueue.main.async {
                if let error {
                    feedbackStatus = "Feedback failed: \(error.localizedDescription)"
                } else {
                    feedbackStatus = "Feedback sent — thank you!"
                    ActivityLog.record(.feedback, detail: "\u{201C}\(title)\u{201D}")
                    entries = ActivityLog.all()
                    feedbackTitle = ""
                    feedbackDescription = ""
                }
            }
        }
    }

    private func openDashboard() {
        var components = URLComponents(string: "https://app.bugsplat.com/v2/dashboard")
        components?.queryItems = [URLQueryItem(name: "database", value: database)]
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    ContentView()
}
