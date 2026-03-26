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

        // Add a "Send Feedback" button that presents a dialog
        let feedbackButton = UIButton(type: .system)
        feedbackButton.setTitle("Send Feedback", for: .normal)
        feedbackButton.addTarget(self, action: #selector(showFeedbackDialog), for: .touchUpInside)
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

    @objc func showFeedbackDialog() {
        let alert = UIAlertController(title: "Send Feedback", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Title" }
        alert.addTextField { $0.placeholder = "Description" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Send", style: .default) { _ in
            guard let title = alert.textFields?[0].text, !title.isEmpty else { return }
            let description = alert.textFields?[1].text

            BugSplat.shared().postFeedback(
                title: title,
                description: description?.isEmpty == false ? description : nil,
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
        })
        present(alert, animated: true)
    }

}
