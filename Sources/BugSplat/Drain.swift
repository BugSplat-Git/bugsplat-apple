import Foundation

/// What happens to reports left over from previous sessions once `start` succeeds.
///
/// macOS: nothing. Capture, dialog and upload ran out of process at crash time; anything still
/// pending is a retryable failure the native side owns, and the app can always call
/// `BugSplat.postPendingReports()` itself.
///
/// iOS/tvOS: capture is in process, so the previous session's reports are handled here at the
/// next launch: uploaded silently under `.quiet` (or once the user chose "Always Send"), left
/// alone under `.manual`, and offered through the in-app prompt under `.dialog`.
enum PendingReportDrain {
    static let alwaysSendKey = "com.bugsplat.alwaysSend"

    static var alwaysSend: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysSendKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysSendKey) }
    }

    static func runAfterStart(options: BugSplat.Options) {
        #if os(iOS) || os(tvOS)
        let pending = BugSplat.pendingReports()
        guard !pending.isEmpty else { return }
        switch options.uploadPolicy {
        case .manual:
            return
        case .quiet:
            sendAll(pending)
        case .dialog:
            if alwaysSend {
                sendAll(pending)
            } else if options.promptForPendingReports {
                Task { @MainActor in ReportPrompt.present(pending) }
            }
        }
        #else
        _ = options
        #endif
    }

    /// Uploads the reports one after another on the upload queue; the delegate hears about each.
    static func sendAll(_ reports: [PendingReport], user: String? = nil, email: String? = nil, description: String? = nil) {
        BugSplat.uploadQueue.async {
            for report in reports {
                do {
                    _ = try BugSplat.sendSync(report, user: user, email: email, description: description)
                } catch {
                    BugSplat.notifyDelegate { $0.bugSplatDidFailToSendReport?(error, folder: report.folder) }
                }
            }
        }
    }

    static func discardAll(_ reports: [PendingReport]) {
        for report in reports { try? BugSplat.discard(report) }
        BugSplat.notifyDelegate { $0.bugSplatDidCancelSendingReports?() }
    }
}
