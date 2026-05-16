//
//  ViewController.swift
//  BugSplatTest-UIKit-Swift
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import UIKit
import BugSplat

final class ViewController: UIViewController {

    // MARK: - State

    private var entries: [ActivityEntry] = []
    private var feedbackStatus: String?

    // MARK: - Views

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleRowDatabaseBadgeContainer = UIView()
    private let recentActivityCard = UIView()
    private let recentActivityContent = UIStackView()
    private let footerLabel = UILabel()

    private var database: String {
        BugSplat.shared().bugSplatDatabase ?? "—"
    }

    private var sdkVersion: String {
        let v = Bundle(for: BugSplat.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(v ?? "—")"
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DemoColor.screenBg
        buildLayout()
        refreshActivity()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshActivity()
    }

    @objc private func appDidBecomeActive() {
        refreshActivity()
    }

    // MARK: - Layout

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 0
        scrollView.addSubview(contentStack)

        let safe = view.safeAreaLayoutGuide
        let cg = scrollView.contentLayoutGuide
        let fg = scrollView.frameLayoutGuide

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safe.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: cg.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: cg.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: cg.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: cg.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: fg.widthAnchor, constant: -40),
        ])

        // Top bar
        let topBar = makeTopBar()
        contentStack.addArrangedSubview(topBar)
        contentStack.setCustomSpacing(22, after: topBar)

        // Title row
        let titleRow = makeTitleRow()
        contentStack.addArrangedSubview(titleRow)
        contentStack.setCustomSpacing(6, after: titleRow)

        // Subtitle
        let subtitle = UILabel()
        subtitle.text = "Trigger an event. We catch it, group it, route it to your dashboard."
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = DemoColor.textSecondary
        subtitle.numberOfLines = 0
        contentStack.addArrangedSubview(subtitle)
        contentStack.setCustomSpacing(22, after: subtitle)

        // "TRIGGER AN EVENT" section header
        let triggerHeader = makeSectionHeader("TRIGGER AN EVENT")
        contentStack.addArrangedSubview(triggerHeader)
        contentStack.setCustomSpacing(12, after: triggerHeader)

        // Event cards
        let cardsStack = UIStackView()
        cardsStack.axis = .vertical
        cardsStack.spacing = 12
        cardsStack.alignment = .fill

        let crashCard = EventCardView(icon: "splat_crash",
                                      title: "Crash",
                                      subtitle: "Native crash · stack + threads + memory")
        crashCard.addTarget(self, action: #selector(triggerCrash), for: .touchUpInside)

        let errorCard = EventCardView(icon: "splat_error",
                                      title: "Non-Crash Error",
                                      subtitle: "Exception caught · app keeps running")
        errorCard.addTarget(self, action: #selector(triggerNonCrashError), for: .touchUpInside)

        let feedbackCard = EventCardView(icon: "splat_feedback",
                                         title: "User Feedback",
                                         subtitle: "Open the feedback sheet")
        feedbackCard.addTarget(self, action: #selector(presentFeedbackSheet), for: .touchUpInside)

        let hangCard = EventCardView(icon: "splat_hang",
                                     title: "Hang",
                                     subtitle: "Freeze main thread for 8 seconds")
        hangCard.addTarget(self, action: #selector(presentHangConfirm), for: .touchUpInside)

        [crashCard, errorCard, feedbackCard, hangCard].forEach { cardsStack.addArrangedSubview($0) }
        contentStack.addArrangedSubview(cardsStack)
        contentStack.setCustomSpacing(18, after: cardsStack)

        // Recent Activity card
        buildRecentActivityCard()
        contentStack.addArrangedSubview(recentActivityCard)
        contentStack.setCustomSpacing(18, after: recentActivityCard)

        // Footer
        footerLabel.font = .systemFont(ofSize: 13)
        footerLabel.textColor = DemoColor.textTertiary
        footerLabel.textAlignment = .center
        footerLabel.numberOfLines = 0
        footerLabel.text = "Shake the device to send feedback anytime."
        contentStack.addArrangedSubview(footerLabel)
    }

    private func makeTopBar() -> UIView {
        let wordmark = UIImageView(image: UIImage(named: "bugsplat_wordmark"))
        wordmark.translatesAutoresizingMaskIntoConstraints = false
        wordmark.contentMode = .scaleAspectFit
        wordmark.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let version = UILabel()
        version.translatesAutoresizingMaskIntoConstraints = false
        version.text = sdkVersion
        version.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        version.textColor = DemoColor.textSecondary
        version.setContentHuggingPriority(.required, for: .horizontal)

        let pill = StatusPill(connected: true)
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.setContentHuggingPriority(.required, for: .horizontal)

        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(wordmark)
        bar.addSubview(version)
        bar.addSubview(pill)

        NSLayoutConstraint.activate([
            wordmark.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            wordmark.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            wordmark.heightAnchor.constraint(equalToConstant: 28),
            wordmark.topAnchor.constraint(equalTo: bar.topAnchor),
            wordmark.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            version.trailingAnchor.constraint(equalTo: pill.leadingAnchor, constant: -10),
            version.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            pill.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            pill.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            wordmark.trailingAnchor.constraint(lessThanOrEqualTo: version.leadingAnchor, constant: -10),
        ])

        return bar
    }

    private func makeTitleRow() -> UIView {
        let title = UILabel()
        title.text = "BugSplat SDK · Demo"
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textColor = DemoColor.textPrimary
        title.setContentHuggingPriority(.required, for: .horizontal)

        let badge = DatabaseBadge(text: database)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Use a stack view so trailing spacer pushes the badge alongside the title
        // and the badge stays vertically centered on the title's cap. Avoid relying
        // on firstBaselineAnchor across a custom UIView container, which defaults to
        // the container's bottom and pushes the badge onto the next visual line.
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [title, badge, spacer])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeSectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        // Tracking of 1.2 via attributed string kern.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: DemoColor.textTertiary,
            .kern: 1.2
        ]
        label.attributedText = NSAttributedString(string: text, attributes: attrs)
        return label
    }

    private func buildRecentActivityCard() {
        recentActivityCard.translatesAutoresizingMaskIntoConstraints = false
        recentActivityCard.backgroundColor = DemoColor.cardBg
        recentActivityCard.layer.cornerRadius = 14
        recentActivityCard.layer.cornerCurve = .continuous
        recentActivityCard.layer.borderColor = DemoColor.cardStroke.cgColor
        recentActivityCard.layer.borderWidth = 1

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let title = makeSectionHeader("RECENT ACTIVITY")
        title.translatesAutoresizingMaskIntoConstraints = false

        let dashboard = UIButton(type: .system)
        dashboard.translatesAutoresizingMaskIntoConstraints = false
        dashboard.setTitle("View dashboard ↗", for: .normal)
        dashboard.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        dashboard.setTitleColor(DemoColor.link, for: .normal)
        dashboard.contentEdgeInsets = .zero
        dashboard.addTarget(self, action: #selector(openDashboard), for: .touchUpInside)

        header.addSubview(title)
        header.addSubview(dashboard)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.topAnchor.constraint(equalTo: header.topAnchor),
            title.bottomAnchor.constraint(equalTo: header.bottomAnchor),

            dashboard.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            dashboard.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        recentActivityContent.translatesAutoresizingMaskIntoConstraints = false
        recentActivityContent.axis = .vertical
        recentActivityContent.spacing = 10
        recentActivityContent.alignment = .fill

        let outer = UIStackView(arrangedSubviews: [header, recentActivityContent])
        outer.translatesAutoresizingMaskIntoConstraints = false
        outer.axis = .vertical
        outer.spacing = 14
        outer.alignment = .fill
        recentActivityCard.addSubview(outer)

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: recentActivityCard.topAnchor, constant: 14),
            outer.bottomAnchor.constraint(equalTo: recentActivityCard.bottomAnchor, constant: -14),
            outer.leadingAnchor.constraint(equalTo: recentActivityCard.leadingAnchor, constant: 16),
            outer.trailingAnchor.constraint(equalTo: recentActivityCard.trailingAnchor, constant: -16),
        ])
    }

    // MARK: - Data refresh

    private func refreshActivity() {
        entries = ActivityLog.all()
        renderRecentActivity()
        renderFooter()
    }

    private func renderRecentActivity() {
        recentActivityContent.arrangedSubviews.forEach { v in
            recentActivityContent.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        if entries.isEmpty {
            let empty = UILabel()
            empty.text = "No events yet — tap a card above to get started."
            empty.font = .systemFont(ofSize: 14)
            empty.textColor = DemoColor.textTertiary
            empty.numberOfLines = 0
            recentActivityContent.addArrangedSubview(empty)
        } else {
            for entry in entries {
                recentActivityContent.addArrangedSubview(RecentActivityRow(entry: entry))
            }
        }
    }

    private func renderFooter() {
        footerLabel.text = feedbackStatus ?? "Shake the device to send feedback anytime."
    }

    // MARK: - Actions

    @objc private func triggerCrash() {
        // Record synchronously before the crash so the entry survives process death
        // and shows up when the app relaunches.
        ActivityLog.record(.crash, detail: "Native crash triggered")
        refreshActivity()
        let prop: Int? = nil
        _ = prop!
    }

    @objc private func triggerNonCrashError() {
        // Demo: pretend we caught an exception. Real apps would put a do/try/catch
        // around an actual risky operation and report the type name here.
        ActivityLog.record(.error, detail: "NSInvalidArgumentException caught")
        refreshActivity()
    }

    @objc private func presentFeedbackSheet() {
        let alert = UIAlertController(title: "Send Feedback", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Title" }
        alert.addTextField { $0.placeholder = "Description" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Send", style: .default) { [weak self, weak alert] _ in
            let title = alert?.textFields?[0].text ?? ""
            let description = alert?.textFields?[1].text ?? ""
            self?.sendFeedback(title: title, description: description)
        })
        present(alert, animated: true)
    }

    @objc private func presentHangConfirm() {
        let alert = UIAlertController(
            title: "Simulate Fatal Hang?",
            message: "The main thread will be blocked for 8 seconds. The UI will freeze; the app will not appear to respond until the freeze ends.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Hang App", style: .destructive) { [weak self] _ in
            self?.simulateHang()
        })
        present(alert, animated: true)
    }

    private func simulateHang() {
        ActivityLog.record(.hang, detail: "Main thread frozen")
        refreshActivity()
        // Eight-second freeze - matches the Android demo copy. With the fatal-only
        // hang detector this won't produce a hang report (main recovers), but the
        // local activity entry above shows the user that the event was logged.
        let until = Date(timeIntervalSinceNow: 8)
        while Date() < until { }
    }

    private func sendFeedback(title: String, description: String) {
        feedbackStatus = "Sending..."
        renderFooter()
        BugSplat.shared().postFeedback(
            title: title,
            description: description.isEmpty ? nil : description,
            userName: nil,
            userEmail: nil,
            appKey: nil,
            attachments: nil
        ) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.feedbackStatus = "Feedback failed: \(error.localizedDescription)"
                    self.renderFooter()
                } else {
                    self.feedbackStatus = "Feedback sent — thank you!"
                    let detail = title.isEmpty ? "Feedback submitted" : "\u{201C}\(title)\u{201D}"
                    ActivityLog.record(.feedback, detail: detail)
                    self.refreshActivity()
                }
            }
        }
    }

    @objc private func openDashboard() {
        var components = URLComponents(string: "https://app.bugsplat.com/v2/dashboard")
        components?.queryItems = [URLQueryItem(name: "database", value: database)]
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }
}
