#if canImport(UIKit) && (os(iOS) || os(tvOS))
import UIKit

/// The iOS/tvOS "send report?" prompt: Send / Don't Send / Always Send, with name, email and
/// description fields on iOS (tvOS alerts have no text fields). One prompt covers every report
/// from the previous session.
@MainActor
enum ReportPrompt {
    static func present(_ reports: [PendingReport]) {
        BugSplat.delegate?.bugSplatWillShowReportPrompt?(reportCount: reports.count)
        guard let presenter = topViewController() else {
            // No UI to ask in (extension, headless launch): fall back to sending.
            PendingReportDrain.sendAll(reports)
            return
        }

        let appName = BugSplat.session?.application
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "The app"
        let isHang = reports.contains { $0.kind == .hang }
        let title = isHang ? String(format: Strings.hangTitle, appName) : String(format: Strings.crashTitle, appName)
        let alert = UIAlertController(title: title, message: Strings.message, preferredStyle: .alert)

        #if os(iOS)
        alert.addTextField { field in
            field.placeholder = Strings.namePlaceholder
            field.text = BugSplat.user
            field.textContentType = .name
        }
        alert.addTextField { field in
            field.placeholder = Strings.emailPlaceholder
            field.text = BugSplat.email
            field.keyboardType = .emailAddress
            field.textContentType = .emailAddress
            field.autocapitalizationType = .none
        }
        alert.addTextField { field in
            field.placeholder = Strings.descriptionPlaceholder
        }
        #endif

        func entered() -> (user: String?, email: String?, description: String?) {
            #if os(iOS)
            let fields = alert.textFields ?? []
            func value(_ i: Int) -> String? {
                guard fields.indices.contains(i) else { return nil }
                let text = fields[i].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return text.isEmpty ? nil : text
            }
            return (value(0), value(1), value(2))
            #else
            return (nil, nil, nil)
            #endif
        }

        alert.addAction(UIAlertAction(title: Strings.dontSend, style: .cancel) { _ in
            PendingReportDrain.discardAll(reports)
        })
        alert.addAction(UIAlertAction(title: Strings.send, style: .default) { _ in
            let e = entered()
            rememberUserDetails(e.user, e.email)
            PendingReportDrain.sendAll(reports, user: e.user, email: e.email, description: e.description)
        })
        alert.addAction(UIAlertAction(title: Strings.alwaysSend, style: .default) { _ in
            let e = entered()
            rememberUserDetails(e.user, e.email)
            PendingReportDrain.alwaysSend = true
            BugSplat.delegate?.bugSplatWillSendReportsAlways?()
            PendingReportDrain.sendAll(reports, user: e.user, email: e.email, description: e.description)
        })
        presenter.present(alert, animated: true)
    }

    /// What the user typed becomes the session's user/email so later reports carry it too.
    private static func rememberUserDetails(_ user: String?, _ email: String?) {
        if let user { BugSplat.user = user }
        if let email { BugSplat.email = email }
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { ($0.activationState == .foregroundActive ? 0 : 1) < ($1.activationState == .foregroundActive ? 0 : 1) }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    enum Strings {
        static let crashTitle = NSLocalizedString("BugSplat.prompt.crashTitle", bundle: .module, value: "%@ quit unexpectedly", comment: "Crash prompt title; %@ is the app name")
        static let hangTitle = NSLocalizedString("BugSplat.prompt.hangTitle", bundle: .module, value: "%@ stopped responding", comment: "Hang prompt title; %@ is the app name")
        static let message = NSLocalizedString("BugSplat.prompt.message", bundle: .module, value: "Would you like to send a report to help fix the problem?", comment: "Prompt body")
        static let namePlaceholder = NSLocalizedString("BugSplat.prompt.name", bundle: .module, value: "Name (optional)", comment: "Text field placeholder")
        static let emailPlaceholder = NSLocalizedString("BugSplat.prompt.email", bundle: .module, value: "Email (optional)", comment: "Text field placeholder")
        static let descriptionPlaceholder = NSLocalizedString("BugSplat.prompt.description", bundle: .module, value: "What were you doing? (optional)", comment: "Text field placeholder")
        static let send = NSLocalizedString("BugSplat.prompt.send", bundle: .module, value: "Send", comment: "Button")
        static let dontSend = NSLocalizedString("BugSplat.prompt.dontSend", bundle: .module, value: "Don't Send", comment: "Button")
        static let alwaysSend = NSLocalizedString("BugSplat.prompt.alwaysSend", bundle: .module, value: "Always Send", comment: "Button")
    }
}
#endif
