//
//  ViewController.swift
//  BugSplatTest-UIKit-Swift
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import UIKit
import BugSplat


class ViewController: UIViewController {
    var nonOptional: NSObject!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        nonOptional = nil

        // Attributes can be set any time and can contain dynamic values
        // Attributes set in this app session will only appear if the app session in which they are set terminates with an app crash
        BugSplat.shared().set(NSDate().description, for: "ViewDidLoadDateTime")

        // Add a "Send Feedback" button programmatically
        let feedbackButton = UIButton(type: .system)
        feedbackButton.setTitle("Send Feedback", for: .normal)
        feedbackButton.addTarget(self, action: #selector(sendFeedback), for: .touchUpInside)
        feedbackButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(feedbackButton)
        NSLayoutConstraint.activate([
            feedbackButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            feedbackButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 60)
        ])
    }

    @IBAction func crashApp(_ sender: Any) {
        // intentially crash app here to demonstrate BugSplat's crash reporting capabilities
        let description = nonOptional!.debugDescription
        print(description)
    }

    @objc func sendFeedback() {
        BugSplat.shared().postFeedback(
            title: "User Feedback",
            description: "This is a test feedback submission from the UIKit Swift example app.",
            userName: nil,
            userEmail: nil,
            appKey: nil,
            attachments: nil
        ) { error in
            if let error {
                print("Feedback failed: \(error.localizedDescription)")
            } else {
                print("Feedback submitted successfully!")
            }
        }
    }

}
