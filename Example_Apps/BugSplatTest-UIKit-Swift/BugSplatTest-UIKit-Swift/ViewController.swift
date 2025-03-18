//
//  ViewController.swift
//  BugSplatTest-UIKit-Swift
//
//  Copyright © 2024 BugSplat, LLC. All rights reserved.
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
    }

    @IBAction func crashApp(_ sender: Any) {
        // intentially crash app here to demonstrate BugSplat's crash reporting capabilities
        let description = nonOptional!.debugDescription
        print(description)
    }
    
}
