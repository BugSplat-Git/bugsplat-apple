//
//  FeedbackSheet.swift
//  BugSplatTest-SwiftUI-SPM
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI
import BugSplat

/// User feedback (BugSplat report type 36): a title, a description and optional attachments,
/// uploaded through the same store and uploader as a crash.
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activity: Activity
    @State private var title = ""
    @State private var details = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("What happened?", text: $details, axis: .vertical).lineLimit(4...8)
            }
            .navigationTitle("Feedback")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sending..." : "Send") { send() }.disabled(title.isEmpty || sending)
                }
            }
        }
    }

    private func send() {
        sending = true
        Task {
            do {
                let result = try await BugSplat.postFeedback(title: title, description: details)
                activity.log("feedback \(result.crashId) \(result.infoURL?.absoluteString ?? "")")
            } catch {
                activity.log("feedback failed: \(error)")
            }
            sending = false
            dismiss()
        }
    }
}
