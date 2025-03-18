//
//  BugSplatTest-SwiftUIApp.swift
//  BugSplatTest-SwiftUI
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI
import BugSplat

@main
struct BugSplatTestSwiftUIApp: App {
    private let bugSplat = BugSplatInitializer()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@objc class BugSplatInitializer: NSObject, BugSplatDelegate {

    override init() {
        super.init()
        
        // Initialize BugSplat
        let bugSplat = BugSplat.shared()
        bugSplat.delegate = self
        bugSplat.autoSubmitCrashReport = false

        // Optionally, add some attributes to your crash reports.
        // Attributes are artibrary key/value pairs that are searchable in the BugSplat dashboard.
        bugSplat.set("Value of Plain Attribute", for: "PlainAttribute")
        bugSplat.set("Value of not so plain <value> Attribute", for: "NotSoPlainAttribute")
        bugSplat.set("Launch Date <![CDATA[\(Date.now)]]> Value", for: "CDATAExample")
        bugSplat.set("<!-- 'value is > or < before' --> \(Date.now)", for: "CommentExample")
        bugSplat.set("This value will get XML escaping because of 'this' and & and < and >", for: "EscapingExample")
    
        // Don't forget to call start after you've finished configuring BugSplat
        bugSplat.start()
    }

    // MARK: BugSplatDelegate
    func bugSplatWillSendCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillSendCrashReportsAlways(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatDidFinishSendingCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillCancelSendingCrashReport(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplatWillShowSubmitCrashReportAlert(_ bugSplat: BugSplat) {
        print("\(#file) - \(#function)")
    }

    func bugSplat(_ bugSplat: BugSplat, didFailWithError error: Error) {
        print("\(#file) - \(#function)")
    }
}
