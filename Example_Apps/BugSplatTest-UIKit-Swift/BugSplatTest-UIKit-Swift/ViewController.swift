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

        // Add a "Simulate Hang" button for demoing fatal-hang detection.
        let hangButton = UIButton(type: .system)
        hangButton.setTitle("Simulate Hang", for: .normal)
        hangButton.addTarget(self, action: #selector(simulateHang), for: .touchUpInside)
        hangButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hangButton)
        NSLayoutConstraint.activate([
            hangButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hangButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 100)
        ])
    }

    @IBAction func crashApp(_ sender: Any) {
        // intentially crash app here to demonstrate BugSplat's crash reporting capabilities
        let description = nonOptional!.debugDescription
        print(description)
    }

    @objc func simulateHang() {
        let alert = UIAlertController(
            title: "Simulate Fatal Hang?",
            message: "The main thread will be blocked indefinitely. The UI will freeze and the only way to recover is to force-quit the app.\n\nOn a real device, swipe up from the app switcher. On the iOS Simulator, swipe-up only backgrounds the app - run `xcrun simctl terminate booted com.bugsplat.BugSplatTest-UIKit-Swift` from a terminal instead.\n\nOn the next launch, a fatal-hang report will be uploaded. Continue?",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Hang App", style: .destructive) { _ in
            // Blocks the main thread forever so the only way to exit is to force-quit
            // the app. That produces a fatal-hang report that is uploaded on the next
            // launch. If the main thread were allowed to recover, the persisted report
            // would be discarded because non-fatal hangs are intentionally not reported.
            print("BugSplat sample: Simulating main-thread hang. Force-quit to see a fatal-hang report on the next launch.")
            while true { }
        })
        present(alert, animated: true)
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
            ) { [weak self] error in
                DispatchQueue.main.async {
                    let message = error != nil ? "Failed: \(error!.localizedDescription)" : "Feedback submitted successfully!"
                    let confirm = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                    confirm.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(confirm, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }

}
