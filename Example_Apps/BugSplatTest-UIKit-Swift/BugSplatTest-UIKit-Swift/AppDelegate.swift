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
    
    /// URL for the sample log file that will be attached to crash reports
    private var logFileURL: URL?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // Create a sample log file for attachment demonstration
        createSampleLogFile()

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
    
    // MARK: - Sample Log File
    
    /// Creates a sample log file in the documents directory for attachment demonstration
    private func createSampleLogFile() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Could not access documents directory")
            return
        }
        
        logFileURL = documentsURL.appendingPathComponent("sample_log.txt")
        
        let logContent = """
        =====================================
        BugSplat Sample Log File
        =====================================
        App Launch: \(Date())
        Device: \(UIDevice.current.model)
        System Version: \(UIDevice.current.systemVersion)
        
        This is a sample log file demonstrating how to attach
        files to BugSplat crash reports.
        
        You can use this pattern to attach:
        - Application logs
        - Configuration files
        - User session data
        - Any other relevant debugging information
        
        Log entries:
        [\(Date())] INFO: Application started
        [\(Date())] DEBUG: BugSplat initialized
        [\(Date())] INFO: Sample log file created for attachment demo
        =====================================
        """
        
        do {
            try logContent.write(to: logFileURL!, atomically: true, encoding: .utf8)
            print("Sample log file created at: \(logFileURL!.path)")
        } catch {
            print("Failed to create sample log file: \(error)")
            logFileURL = nil
        }
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
    
    /// Returns a file attachment to include with the crash report
    /// This demonstrates how to attach log files or other data to crash reports
    func attachmentForBugSplat(_ bugSplat: BugSplat) -> BugSplatAttachment? {
        guard let logFileURL = logFileURL,
              let logData = try? Data(contentsOf: logFileURL) else {
            print("Could not read log file for attachment")
            return nil
        }
        
        print("Attaching log file to crash report: \(logFileURL.lastPathComponent)")
        return BugSplatAttachment(
            filename: "sample_log.txt",
            attachmentData: logData,
            contentType: "text/plain"
        )
    }
}
