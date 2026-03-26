//
//  ContentView.swift
//  BugSplatTest-SwiftUI
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI
import BugSplat

struct ContentView: View {
    @State var isFeature1Active: Bool = false
    @State var isFeature2Active: Bool = false
    @State var isFeature3Active: Bool = false
    @State var showFeedbackAlert = false
    @State var feedbackTitle = ""
    @State var feedbackDescription = ""
    @State var feedbackStatus: String?

    let prop: Int? = nil

    var body: some View {
        VStack {
            Toggle(isOn: $isFeature1Active) {
                isFeature1Active ? Text("Feature 1 is Active") : Text("Feature 1 is Inactive")
            }
            .padding()
            .foregroundColor(.white)
            .background(Color.secondary)
            .cornerRadius(10)
            .padding()

            Toggle(isOn: $isFeature2Active) {
                isFeature2Active ? Text("Feature 2 is Active") : Text("Feature 2 is Inactive")
            }
            .padding()
            .foregroundColor(.white)
            .background(Color.secondary)
            .cornerRadius(10)
            .padding()

            Toggle(isOn: $isFeature3Active) {
                isFeature3Active ? Text("Feature 3 is Active") : Text("Feature 3 is Inactive")
            }
            .padding()
            .foregroundColor(.white)
            .background(Color.secondary)
            .cornerRadius(10)
            .padding()

            Button("Crash!") {
                _ = prop!
            }
            .padding()
            .foregroundColor(.white)
            .background(Color.accentColor)
            .cornerRadius(10)

            Button("Send Feedback") {
                showFeedbackAlert = true
            }
            .padding()
            .foregroundColor(.white)
            .background(Color.green)
            .cornerRadius(10)

            if let feedbackStatus {
                Text(feedbackStatus)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .onChange(of: isFeature1Active) {
            update(attribute: "Feature1", value: isFeature1Active.description)
        }
        .onChange(of: isFeature2Active) {
            update(attribute: "Feature2", value: isFeature2Active.description)
        }
        .onChange(of: isFeature3Active) {
            update(attribute: "Feature3", value: isFeature3Active.description)
        }
        .alert("Send Feedback", isPresented: $showFeedbackAlert) {
            TextField("Title", text: $feedbackTitle)
            TextField("Description", text: $feedbackDescription)
            Button("Send") { sendFeedback() }
            Button("Cancel", role: .cancel) { }
        }
    }

    func update(attribute: String, value: String?) {
        print("update(\(attribute), value: \(value ?? "nil")")
        BugSplat.shared().set(value, for: attribute)
    }

    func sendFeedback() {
        feedbackStatus = "Sending..."
        BugSplat.shared().postFeedback(
            title: feedbackTitle,
            description: feedbackDescription.isEmpty ? nil : feedbackDescription,
            userName: nil,
            userEmail: nil,
            appKey: nil,
            attachments: nil
        ) { error in
            DispatchQueue.main.async {
                if let error {
                    feedbackStatus = "Failed: \(error.localizedDescription)"
                } else {
                    feedbackStatus = "Feedback sent!"
                    feedbackTitle = ""
                    feedbackDescription = ""
                }
            }
        }
    }

}

#Preview {
    ContentView()
}
