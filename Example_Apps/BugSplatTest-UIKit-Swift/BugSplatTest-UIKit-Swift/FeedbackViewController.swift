//
//  FeedbackViewController.swift
//  BugSplatTest-UIKit-Swift
//
//  The redesigned User Feedback experience: a bottom-sheet form for composing
//  feedback, and a thank-you confirmation shown in the same sheet after a
//  successful submit. Mirrors the bugsplat-android demo refresh.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers
import BugSplat

/// Feedback category shown in the segmented selector. The raw value is sent to
/// BugSplat as the `category` custom attribute.
enum FeedbackCategory: String, CaseIterable {
    case bug = "Bug"
    case feature = "Feature"
    case other = "Other"
}

/// Locates the current session's log file the app writes at launch (see `AppDelegate`)
/// so it can be attached to feedback when the user opts in. Each session's log is
/// named after `BugSplat.shared().sessionID`; since feedback is sent live during the
/// current session, the current sessionID identifies the right file.
enum SampleLog {
    static var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SessionLogs", isDirectory: true)
            .appendingPathComponent("\(BugSplat.shared().sessionID.uuidString).log")
    }

    static func attachment() -> BugSplatAttachment? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return BugSplatAttachment(filename: "session.log",
                                  attachmentData: data,
                                  contentType: "text/plain")
    }
}

final class FeedbackViewController: UIViewController {

    /// Called after the sheet is dismissed so the presenter can refresh state
    /// (a page-sheet dismissal does not trigger the presenter's viewWillAppear).
    var onDismiss: (() -> Void)?

    // MARK: - State

    private var category: FeedbackCategory = .bug
    private var pickedFileName: String?
    private var pickedFileData: Data?
    private var isSubmitting = false

    private var database: String {
        BugSplat.shared().bugSplatDatabase ?? "—"
    }

    // MARK: - Views

    private let formContainer = UIView()
    private let thanksContainer = UIView()
    private let formScrollView = UIScrollView()

    /// Lifted by the keyboard handler so the footer + scroll view stay above the keyboard.
    private var layoutBottomConstraint: NSLayoutConstraint!

    private let segmented = UISegmentedControl(items: FeedbackCategory.allCases.map { $0.rawValue })
    private let titleField = UITextField()
    private let descriptionView = UITextView()
    private let nameField = UITextField()
    private let emailField = UITextField()
    private let includeLogsSwitch = UISwitch()
    private let errorLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let sendSpinner = UIActivityIndicatorView(style: .medium)

    private let attachmentRow = UIView()
    private let attachmentTypeChip = UILabel()
    private let attachmentNameLabel = UILabel()
    private let attachmentDetailLabel = UILabel()
    private let attachmentActionButton = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DemoColor.cardBg
        buildForm()
        buildThanksPlaceholder()
        renderAttachmentRow()
        updateSendEnabled()
        installKeyboardHandling()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Only when the sheet is actually going away — not when it is merely
        // covered by a controller it presented (e.g. the document picker).
        if isBeingDismissed {
            onDismiss?()
        }
    }

    // MARK: - Form layout

    private func buildForm() {
        formContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(formContainer)
        NSLayoutConstraint.activate([
            formContainer.topAnchor.constraint(equalTo: view.topAnchor),
            formContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            formContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            formContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Header
        let header = makeHeader(title: "Send feedback")
        let headerDivider = makeDivider()

        // Footer (hint + send button)
        let footer = makeFormFooter()

        // Scrollable field content
        let scrollView = formScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive

        let fields = UIStackView()
        fields.translatesAutoresizingMaskIntoConstraints = false
        fields.axis = .vertical
        fields.spacing = 18
        fields.alignment = .fill

        segmented.selectedSegmentIndex = 0
        segmented.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)
        fields.addArrangedSubview(segmented)

        configureTextField(titleField)
        fields.addArrangedSubview(makeField(label: "Title", required: true, input: boxed(titleField)))

        descriptionView.font = .systemFont(ofSize: 15)
        descriptionView.textColor = DemoColor.textPrimary
        descriptionView.backgroundColor = .clear
        descriptionView.isScrollEnabled = false
        descriptionView.textContainerInset = UIEdgeInsets(top: 7, left: 8, bottom: 7, right: 8)
        descriptionView.heightAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
        fields.addArrangedSubview(makeField(label: "Description", required: false, input: boxed(descriptionView)))

        configureTextField(nameField)
        nameField.textContentType = .name
        fields.addArrangedSubview(makeField(label: "Name", required: false, input: boxed(nameField)))

        configureTextField(emailField)
        emailField.textContentType = .emailAddress
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        fields.addArrangedSubview(makeField(label: "Email", required: false, input: boxed(emailField)))

        buildAttachmentRow()
        fields.addArrangedSubview(makeField(label: "Attachment", required: false, input: attachmentRow))

        fields.addArrangedSubview(makeIncludeLogsRow())

        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = DemoColor.asterisk
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        fields.addArrangedSubview(errorLabel)

        scrollView.addSubview(fields)

        let layout = UIStackView(arrangedSubviews: [header, headerDivider, scrollView, footer])
        layout.translatesAutoresizingMaskIntoConstraints = false
        layout.axis = .vertical
        layout.alignment = .fill
        formContainer.addSubview(layout)

        layoutBottomConstraint = layout.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor)

        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: formContainer.safeAreaLayoutGuide.topAnchor),
            layout.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            layoutBottomConstraint,

            fields.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            fields.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            fields.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            fields.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            fields.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    private func makeHeader(title: String) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = DemoColor.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false

        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = DemoColor.textSecondary
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(label)
        bar.addSubview(close)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            label.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            label.topAnchor.constraint(equalTo: bar.topAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -16),
            close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
            close.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func makeFormFooter() -> UIView {
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setTitle("Send feedback  →", for: .normal)
        sendButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.backgroundColor = DemoColor.feedbackAccent
        sendButton.layer.cornerRadius = 12
        sendButton.layer.cornerCurve = .continuous
        sendButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        sendButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        sendSpinner.translatesAutoresizingMaskIntoConstraints = false
        sendSpinner.color = .white
        sendSpinner.hidesWhenStopped = true
        sendButton.addSubview(sendSpinner)
        NSLayoutConstraint.activate([
            sendSpinner.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
            sendSpinner.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
        ])

        let stack = UIStackView(arrangedSubviews: [sendButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = DemoColor.footerBg
        let divider = makeDivider()
        container.addSubview(divider)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: container.topAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func buildAttachmentRow() {
        attachmentRow.translatesAutoresizingMaskIntoConstraints = false
        attachmentRow.backgroundColor = DemoColor.cardBg
        attachmentRow.layer.cornerRadius = 10
        attachmentRow.layer.cornerCurve = .continuous
        attachmentRow.layer.borderColor = DemoColor.cardStroke.cgColor
        attachmentRow.layer.borderWidth = 1

        attachmentTypeChip.translatesAutoresizingMaskIntoConstraints = false
        attachmentTypeChip.font = .systemFont(ofSize: 11, weight: .semibold)
        attachmentTypeChip.textColor = DemoColor.textSecondary
        attachmentTypeChip.textAlignment = .center
        attachmentTypeChip.backgroundColor = DemoColor.badgeBg
        attachmentTypeChip.layer.cornerRadius = 8
        attachmentTypeChip.layer.masksToBounds = true

        attachmentNameLabel.translatesAutoresizingMaskIntoConstraints = false
        attachmentNameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        attachmentNameLabel.textColor = DemoColor.textPrimary
        attachmentNameLabel.lineBreakMode = .byTruncatingMiddle

        attachmentDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        attachmentDetailLabel.font = .systemFont(ofSize: 12)
        attachmentDetailLabel.textColor = DemoColor.textTertiary

        attachmentActionButton.translatesAutoresizingMaskIntoConstraints = false
        attachmentActionButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        attachmentActionButton.setTitleColor(DemoColor.link, for: .normal)
        attachmentActionButton.addTarget(self, action: #selector(pickFileTapped), for: .touchUpInside)
        attachmentActionButton.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [attachmentNameLabel, attachmentDetailLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        attachmentRow.addSubview(attachmentTypeChip)
        attachmentRow.addSubview(textStack)
        attachmentRow.addSubview(attachmentActionButton)

        NSLayoutConstraint.activate([
            attachmentTypeChip.leadingAnchor.constraint(equalTo: attachmentRow.leadingAnchor, constant: 12),
            attachmentTypeChip.centerYAnchor.constraint(equalTo: attachmentRow.centerYAnchor),
            attachmentTypeChip.widthAnchor.constraint(equalToConstant: 44),
            attachmentTypeChip.heightAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(equalTo: attachmentTypeChip.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: attachmentRow.centerYAnchor),

            attachmentActionButton.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 8),
            attachmentActionButton.trailingAnchor.constraint(equalTo: attachmentRow.trailingAnchor, constant: -12),
            attachmentActionButton.centerYAnchor.constraint(equalTo: attachmentRow.centerYAnchor),

            attachmentRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 68),
        ])
    }

    private func renderAttachmentRow() {
        if let name = pickedFileName, let data = pickedFileData {
            let ext = (name as NSString).pathExtension.uppercased()
            attachmentTypeChip.text = ext.isEmpty ? "FILE" : ext
            attachmentTypeChip.isHidden = false
            attachmentNameLabel.text = name
            attachmentDetailLabel.text = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            attachmentDetailLabel.isHidden = false
            attachmentActionButton.setTitle("Replace", for: .normal)
        } else {
            attachmentTypeChip.isHidden = true
            attachmentNameLabel.text = "No file selected"
            attachmentNameLabel.textColor = DemoColor.textTertiary
            attachmentDetailLabel.isHidden = true
            attachmentActionButton.setTitle("Add", for: .normal)
        }
    }

    private func makeIncludeLogsRow() -> UIView {
        let title = UILabel()
        title.text = "Include logs"
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = DemoColor.textPrimary

        let subtitle = UILabel()
        subtitle.text = "Attach this session's log file"
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = DemoColor.textTertiary

        let textStack = UIStackView(arrangedSubviews: [title, subtitle])
        textStack.axis = .vertical
        textStack.spacing = 2

        includeLogsSwitch.isOn = true
        includeLogsSwitch.onTintColor = DemoColor.feedbackAccent
        includeLogsSwitch.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [textStack, includeLogsSwitch])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    // MARK: - Field helpers

    private func configureTextField(_ field: UITextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 15)
        field.textColor = DemoColor.textPrimary
        field.borderStyle = .none
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
    }

    /// Wraps an input view in a rounded, outlined box.
    private func boxed(_ input: UIView) -> UIView {
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.backgroundColor = DemoColor.cardBg
        box.layer.cornerRadius = 10
        box.layer.cornerCurve = .continuous
        box.layer.borderColor = DemoColor.cardStroke.cgColor
        box.layer.borderWidth = 1
        input.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(input)
        // UITextView carries its own insets; UITextField needs explicit padding.
        let inset: CGFloat = input is UITextView ? 0 : 11
        let hInset: CGFloat = input is UITextView ? 0 : 12
        NSLayoutConstraint.activate([
            input.topAnchor.constraint(equalTo: box.topAnchor, constant: inset),
            input.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -inset),
            input.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: hInset),
            input.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -hInset),
        ])
        if !(input is UITextView) {
            input.heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
        }
        return box
    }

    /// A labeled field: a header row (label + red asterisk or "optional") above the input.
    private func makeField(label: String, required: Bool, input: UIView) -> UIView {
        let labelView = UILabel()
        let attributed = NSMutableAttributedString(
            string: label,
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                         .foregroundColor: DemoColor.textPrimary])
        if required {
            attributed.append(NSAttributedString(
                string: " *",
                attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                             .foregroundColor: DemoColor.asterisk]))
        }
        labelView.attributedText = attributed

        let headerRow: UIView
        if required {
            headerRow = labelView
        } else {
            let optional = UILabel()
            optional.text = "optional"
            optional.font = .systemFont(ofSize: 13)
            optional.textColor = DemoColor.textTertiary
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let row = UIStackView(arrangedSubviews: [labelView, spacer, optional])
            row.axis = .horizontal
            row.alignment = .firstBaseline
            headerRow = row
        }

        let stack = UIStackView(arrangedSubviews: [headerRow, input])
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .fill
        return stack
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = DemoColor.cardStroke
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    // MARK: - Keyboard handling

    /// Lifts the form (footer + scroll view) above the keyboard and lets a tap
    /// outside any field dismiss it.
    private func installKeyboardHandling() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardFrameWillChange),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false  // let buttons/controls still receive the tap
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func keyboardFrameWillChange(_ note: Notification) {
        guard let info = note.userInfo,
              let endFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveRaw = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 0

        let endInView = view.convert(endFrame, from: nil)
        let overlap = max(0, view.bounds.maxY - endInView.minY)
        layoutBottomConstraint.constant = -overlap

        UIView.animate(withDuration: duration, delay: 0,
                       options: UIView.AnimationOptions(rawValue: UInt(curveRaw) << 16),
                       animations: { self.view.layoutIfNeeded() },
                       completion: { _ in self.scrollActiveFieldToVisible() })
    }

    /// Keeps the focused field visible after the scroll view shrinks for the keyboard.
    private func scrollActiveFieldToVisible() {
        let fields: [UIView] = [titleField, descriptionView, nameField, emailField]
        guard let active = fields.first(where: { $0.isFirstResponder }) else { return }
        let rect = formScrollView.convert(active.bounds, from: active)
        formScrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -16), animated: true)
    }

    // MARK: - Actions

    @objc private func categoryChanged() {
        category = FeedbackCategory.allCases[segmented.selectedSegmentIndex]
    }

    @objc private func textChanged() {
        updateSendEnabled()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func updateSendEnabled() {
        let hasTitle = !(titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let enabled = hasTitle && !isSubmitting
        sendButton.isEnabled = enabled
        sendButton.alpha = enabled ? 1.0 : 0.45
    }

    @objc private func pickFileTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func setSubmitting(_ submitting: Bool) {
        isSubmitting = submitting
        if submitting {
            sendButton.setTitle("", for: .normal)
            sendSpinner.startAnimating()
        } else {
            sendButton.setTitle("Send feedback  →", for: .normal)
            sendSpinner.stopAnimating()
        }
        segmented.isEnabled = !submitting
        titleField.isEnabled = !submitting
        descriptionView.isEditable = !submitting
        nameField.isEnabled = !submitting
        emailField.isEnabled = !submitting
        includeLogsSwitch.isEnabled = !submitting
        attachmentActionButton.isEnabled = !submitting
        updateSendEnabled()
    }

    @objc private func submitTapped() {
        let trimmedTitle = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        errorLabel.isHidden = true
        setSubmitting(true)

        var attachments: [BugSplatAttachment] = []
        if let name = pickedFileName, let data = pickedFileData {
            let mime = UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            attachments.append(BugSplatAttachment(filename: name, attachmentData: data, contentType: mime))
        }
        if includeLogsSwitch.isOn, let logAttachment = SampleLog.attachment() {
            attachments.append(logAttachment)
        }

        let description = descriptionView.text ?? ""
        let name = nameField.text ?? ""
        let email = emailField.text ?? ""

        BugSplat.shared().postFeedback(
            title: trimmedTitle,
            description: description.isEmpty ? nil : description,
            userName: name.isEmpty ? nil : name,
            userEmail: email.isEmpty ? nil : email,
            appKey: nil,
            attributes: ["category": category.rawValue],
            attachments: attachments.isEmpty ? nil : attachments
        ) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setSubmitting(false)
                if let error = error {
                    self.errorLabel.text = "Feedback failed: \(error.localizedDescription)"
                    self.errorLabel.isHidden = false
                } else {
                    ActivityLog.record(.feedback, detail: "\u{201C}\(trimmedTitle)\u{201D}")
                    self.showThanks(result: result)
                }
            }
        }
    }

    // MARK: - Thank-you screen

    private func buildThanksPlaceholder() {
        thanksContainer.translatesAutoresizingMaskIntoConstraints = false
        thanksContainer.backgroundColor = DemoColor.cardBg
        thanksContainer.isHidden = true
        view.addSubview(thanksContainer)
        NSLayoutConstraint.activate([
            thanksContainer.topAnchor.constraint(equalTo: view.topAnchor),
            thanksContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thanksContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thanksContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func showThanks(result: BugSplatFeedbackResult?) {
        let reportId = result?.crashId.map { "\($0)" }

        // Check circle
        let circle = UIView()
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.backgroundColor = DemoColor.feedbackAccent.withAlphaComponent(0.14)
        circle.layer.cornerRadius = 42
        circle.layer.borderColor = DemoColor.feedbackAccent.withAlphaComponent(0.35).cgColor
        circle.layer.borderWidth = 1
        let check = UIImageView(image: UIImage(systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)))
        check.tintColor = DemoColor.feedbackAccent
        check.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(check)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 84),
            circle.heightAnchor.constraint(equalToConstant: 84),
            check.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
        ])
        let circleWrap = UIView()
        circleWrap.addSubview(circle)
        NSLayoutConstraint.activate([
            circle.topAnchor.constraint(equalTo: circleWrap.topAnchor),
            circle.bottomAnchor.constraint(equalTo: circleWrap.bottomAnchor),
            circle.centerXAnchor.constraint(equalTo: circleWrap.centerXAnchor),
        ])

        let titleLabel = UILabel()
        titleLabel.text = "Feedback sent. Thanks!"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = DemoColor.textPrimary
        titleLabel.textAlignment = .center

        let messageLabel = UILabel()
        messageLabel.text = "Your note made it to the BugSplat team. We reply within a day."
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textColor = DemoColor.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        let reportRow = makeReportIdRow(reportId: reportId)

        let topStack = UIStackView(arrangedSubviews: [circleWrap, titleLabel, messageLabel, reportRow])
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topStack.axis = .vertical
        topStack.alignment = .fill
        topStack.spacing = 16
        topStack.setCustomSpacing(20, after: messageLabel)

        let footer = makeThanksFooter(result: result)

        thanksContainer.addSubview(topStack)
        thanksContainer.addSubview(footer)
        NSLayoutConstraint.activate([
            topStack.centerYAnchor.constraint(equalTo: thanksContainer.centerYAnchor, constant: -40),
            topStack.leadingAnchor.constraint(equalTo: thanksContainer.leadingAnchor, constant: 24),
            topStack.trailingAnchor.constraint(equalTo: thanksContainer.trailingAnchor, constant: -24),

            footer.leadingAnchor.constraint(equalTo: thanksContainer.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: thanksContainer.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: thanksContainer.bottomAnchor),
        ])

        // Swap form -> thanks with a cross-dissolve.
        thanksContainer.alpha = 0
        thanksContainer.isHidden = false
        UIView.transition(with: view, duration: 0.3, options: .transitionCrossDissolve) {
            self.formContainer.isHidden = true
            self.thanksContainer.alpha = 1
        }
    }

    private func makeReportIdRow(reportId: String?) -> UIView {
        let label = UILabel()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: DemoColor.textTertiary,
            .kern: 1.1
        ]
        label.attributedText = NSAttributedString(string: "REPORT ID", attributes: attrs)

        let idLabel = UILabel()
        idLabel.text = reportId ?? "Unavailable"
        idLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        idLabel.textColor = DemoColor.textPrimary

        let row = UIStackView(arrangedSubviews: [label, idLabel])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center

        if let reportId = reportId {
            let copy = UIButton(type: .system)
            copy.setTitle("Copy", for: .normal)
            copy.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
            copy.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            copy.tintColor = DemoColor.textSecondary
            copy.setTitleColor(DemoColor.textSecondary, for: .normal)
            copy.backgroundColor = DemoColor.cardBg
            copy.layer.cornerRadius = 8
            copy.layer.borderColor = DemoColor.cardStroke.cgColor
            copy.layer.borderWidth = 1
            copy.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
            copy.titleEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 0)
            copy.addAction(UIAction { _ in UIPasteboard.general.string = reportId }, for: .touchUpInside)
            copy.setContentHuggingPriority(.required, for: .horizontal)
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)
            row.addArrangedSubview(copy)
        }

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = DemoColor.badgeBg
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    private func makeThanksFooter(result: BugSplatFeedbackResult?) -> UIView {
        let dashboard = UIButton(type: .system)
        dashboard.translatesAutoresizingMaskIntoConstraints = false
        dashboard.setTitle("View on dashboard  ↗", for: .normal)
        dashboard.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        dashboard.setTitleColor(.white, for: .normal)
        dashboard.backgroundColor = DemoColor.feedbackAccent
        dashboard.layer.cornerRadius = 12
        dashboard.layer.cornerCurve = .continuous
        dashboard.heightAnchor.constraint(equalToConstant: 52).isActive = true
        dashboard.addAction(UIAction { [weak self] _ in self?.openReport(result: result) }, for: .touchUpInside)

        let close = UIButton(type: .system)
        close.setTitle("Close", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        close.setTitleColor(DemoColor.textSecondary, for: .normal)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let poweredBy = makePoweredByLabel()

        let stack = UIStackView(arrangedSubviews: [dashboard, close, poweredBy])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 20, bottom: 20, right: 20)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = DemoColor.footerBg
        let divider = makeDivider()
        container.addSubview(divider)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: container.topAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor),
        ])
        return container
    }

    /// "Powered by BugSplat" where the word BugSplat links to bugsplat.com.
    private func makePoweredByLabel() -> UIView {
        let prefix = UILabel()
        prefix.text = "Powered by"
        prefix.font = .systemFont(ofSize: 13)
        prefix.textColor = DemoColor.textTertiary

        let link = UIButton(type: .system)
        link.setTitle("BugSplat", for: .normal)
        link.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        link.setTitleColor(DemoColor.link, for: .normal)
        link.contentEdgeInsets = .zero
        link.addAction(UIAction { _ in
            if let url = URL(string: "https://bugsplat.com") { UIApplication.shared.open(url) }
        }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [prefix, link])
        row.axis = .horizontal
        row.spacing = 4
        row.alignment = .center

        let centered = UIStackView(arrangedSubviews: [UIView(), row, UIView()])
        centered.axis = .horizontal
        centered.distribution = .equalCentering
        return centered
    }

    /// Links directly to the report by id. Feedback reports group by their
    /// (unique) title, so the SDK's infoUrl resolves to a generic page — prefer
    /// the id-scoped crash URL, falling back to the database dashboard.
    private func openReport(result: BugSplatFeedbackResult?) {
        var components: URLComponents?
        if let crashId = result?.crashId {
            components = URLComponents(string: "https://app.bugsplat.com/v2/crash")
            components?.queryItems = [
                URLQueryItem(name: "database", value: database),
                URLQueryItem(name: "id", value: "\(crashId)")
            ]
        } else {
            components = URLComponents(string: "https://app.bugsplat.com/v2/dashboard")
            components?.queryItems = [URLQueryItem(name: "database", value: database)]
        }
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Document picker

extension FeedbackViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            pickedFileData = try Data(contentsOf: url)
            pickedFileName = url.lastPathComponent
            attachmentNameLabel.textColor = DemoColor.textPrimary
            renderAttachmentRow()
        } catch {
            errorLabel.text = "Couldn't read the selected file: \(error.localizedDescription)"
            errorLabel.isHidden = false
        }
    }
}
