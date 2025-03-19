//
//  AppDelegate.swift
//  BugSplatTest-UIKit-Swift
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import UIKit
import BugSplat

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

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
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

extension AppDelegate: BugSplatDelegate {


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
