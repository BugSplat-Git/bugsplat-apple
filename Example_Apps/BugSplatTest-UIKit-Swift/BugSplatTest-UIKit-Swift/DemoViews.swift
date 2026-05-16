//
//  DemoViews.swift
//  BugSplatTest-UIKit-Swift
//
//  Reusable UIKit views for the demo screen: top-bar pill, database badge,
//  event card (tappable), and recent-activity row.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import UIKit

/// Small capsule with a green dot and "Connected" label shown in the top bar.
final class StatusPill: UIView {
    init(connected: Bool = true) {
        super.init(frame: .zero)
        backgroundColor = .white
        layer.borderColor = DemoColor.pillStroke.cgColor
        layer.borderWidth = 1
        layer.cornerCurve = .continuous

        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = DemoColor.connectedDot
        dot.alpha = connected ? 1 : 0.35
        dot.layer.cornerRadius = 4

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = connected ? "Connected" : "Offline"
        label.font = .systemFont(ofSize: 12)
        label.textColor = DemoColor.textPrimary

        addSubview(dot)
        addSubview(label)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// Small rounded-corner pill that shows the BugSplat database name next to the
/// screen title.
final class DatabaseBadge: UIView {
    private let label = UILabel()

    init(text: String) {
        super.init(frame: .zero)
        backgroundColor = DemoColor.badgeBg
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = DemoColor.textSecondary
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Tappable rounded card with a splat icon, bold title, and secondary subtitle.
final class EventCardView: UIControl {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(icon: String, title: String, subtitle: String) {
        super.init(frame: .zero)
        backgroundColor = DemoColor.cardBg
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderColor = DemoColor.cardStroke.cgColor
        layer.borderWidth = 1

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(named: icon)
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = DemoColor.textPrimary
        titleLabel.isUserInteractionEnabled = false

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = DemoColor.textSecondary
        subtitleLabel.numberOfLines = 0
        subtitleLabel.isUserInteractionEnabled = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.isUserInteractionEnabled = false

        addSubview(iconView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 52),
            iconView.heightAnchor.constraint(equalToConstant: 52),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 84),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.alpha = self.isHighlighted ? 0.7 : 1.0
            }
        }
    }
}

/// Single row in the Recent Activity card: colored dot · bold label · secondary
/// detail · trailing relative-time text.
final class RecentActivityRow: UIView {
    init(entry: ActivityEntry) {
        super.init(frame: .zero)

        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = Self.dotColor(for: entry.type)
        dot.layer.cornerRadius = 4

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Self.label(for: entry.type)
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = DemoColor.textPrimary
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let detail = UILabel()
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.text = entry.detail
        detail.font = .systemFont(ofSize: 14)
        detail.textColor = DemoColor.textSecondary
        detail.lineBreakMode = .byTruncatingTail
        detail.numberOfLines = 1

        let time = UILabel()
        time.translatesAutoresizingMaskIntoConstraints = false
        time.text = RelativeTime.string(from: entry.timestamp)
        time.font = .systemFont(ofSize: 13)
        time.textColor = DemoColor.textTertiary
        time.textAlignment = .right
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(dot)
        addSubview(label)
        addSubview(detail)
        addSubview(time)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            detail.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 14),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -10),

            time.trailingAnchor.constraint(equalTo: trailingAnchor),
            time.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
            topAnchor.constraint(equalTo: label.topAnchor).withPriority(.defaultHigh),
            bottomAnchor.constraint(equalTo: label.bottomAnchor).withPriority(.defaultHigh),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func dotColor(for type: ActivityType) -> UIColor {
        switch type {
        case .crash:    return DemoColor.activityCrash
        case .error:    return DemoColor.activityError
        case .feedback: return DemoColor.activityFeedback
        case .hang:     return DemoColor.activityHang
        }
    }

    private static func label(for type: ActivityType) -> String {
        switch type {
        case .crash:    return "Crash"
        case .error:    return "Error"
        case .feedback: return "Feedback"
        case .hang:     return "Hang"
        }
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
