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

    private let titleField: UITextField = {
        let field = UITextField()
        field.placeholder = "Feedback title"
        field.borderStyle = .roundedRect
        return field
    }()

    private let descriptionField: UITextField = {
        let field = UITextField()
        field.placeholder = "Description"
        field.borderStyle = .roundedRect
        return field
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        nonOptional = nil

        // Attributes can be set any time and can contain dynamic values
        // Attributes set in this app session will only appear if the app session in which they are set terminates with an app crash
        BugSplat.shared().set(NSDate().description, for: "ViewDidLoadDateTime")

        // Add feedback input fields and button programmatically
        let feedbackButton = UIButton(type: .system)
        feedbackButton.setTitle("Send Feedback", for: .normal)
        feedbackButton.addTarget(self, action: #selector(sendFeedback), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleField, descriptionField, feedbackButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.topAnchor.constraint(equalTo: view.centerYAnchor, constant: 40),
            titleField.widthAnchor.constraint(equalToConstant: 280),
        ])
    }

    @IBAction func crashApp(_ sender: Any) {
        // intentially crash app here to demonstrate BugSplat's crash reporting capabilities
        let description = nonOptional!.debugDescription
        print(description)
    }

    @objc func sendFeedback() {
        guard let title = titleField.text, !title.isEmpty else { return }
        let description = descriptionField.text

        BugSplat.shared().postFeedback(
            title: title,
            description: description?.isEmpty == false ? description : nil,
            userName: nil,
            userEmail: nil,
            appKey: nil,
            attachments: nil
        ) { error in
            DispatchQueue.main.async { [weak self] in
                if let error {
                    print("Feedback failed: \(error.localizedDescription)")
                } else {
                    print("Feedback submitted successfully!")
                    self?.titleField.text = ""
                    self?.descriptionField.text = ""
                }
            }
        }
    }

}
