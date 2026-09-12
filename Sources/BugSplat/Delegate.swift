import Foundation

/// Lifecycle callbacks for the reports the SDK uploads from inside the app: the iOS/tvOS
/// "send report?" prompt and every `send`/`postPendingReports` drain. All methods are optional
/// and run on the main queue.
///
/// The macOS crash dialog runs out of process in `BugSplatReporter.app` after the app has
/// already died, so it cannot call back into the app; nothing here fires for it.
@objc(BugSplatDelegate)
public protocol BugSplatDelegate: AnyObject {
    /// About to show the in-app prompt for `count` reports from a previous session.
    @objc optional func bugSplatWillShowReportPrompt(reportCount count: Int)

    /// The user chose "Don't Send"; the pending reports were discarded.
    @objc optional func bugSplatDidCancelSendingReports()

    /// The user chose "Always Send"; future reports upload without a prompt.
    @objc optional func bugSplatWillSendReportsAlways()

    /// A report was accepted by the server. `infoURL` is the support-response page when one is
    /// configured for the crash group.
    @objc optional func bugSplatDidSendReport(crashId: Int64, infoURL: URL?, folder: URL)

    /// An upload failed. Retryable failures are retried on a later launch.
    @objc optional func bugSplatDidFailToSendReport(_ error: Error, folder: URL)
}
