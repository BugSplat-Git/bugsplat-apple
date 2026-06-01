//
//  FeedbackSheet.swift
//  BugSplatTest-SwiftUI
//
//  The redesigned User Feedback experience: a bottom-sheet form for composing
//  feedback, and a thank-you confirmation shown in the same sheet after a
//  successful submit. Mirrors the bugsplat-android demo refresh.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BugSplat

// MARK: - Category

/// Feedback category shown in the segmented selector. The raw value is sent to
/// BugSplat as the `category` custom attribute.
enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug = "Bug"
    case feature = "Feature"
    case other = "Other"

    var id: String { rawValue }
}

// MARK: - Sample log helper

/// Locates the `sample_log.txt` file the app writes at launch (see
/// `BugSplatInitializer`) so it can be attached to feedback when the user opts in.
enum SampleLog {
    static var fileURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("sample_log.txt")
    }

    /// Returns the sample log as a `BugSplatAttachment`, or nil if it cannot be read.
    static func attachment() -> BugSplatAttachment? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return BugSplatAttachment(filename: "sample_log.txt",
                                  attachmentData: data,
                                  contentType: "text/plain")
    }
}

// MARK: - Picked attachment

/// A user-chosen file selected via the document picker.
struct PickedAttachment {
    let name: String
    let data: Data

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    var typeChip: String {
        let ext = (name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }

    func bugSplatAttachment() -> BugSplatAttachment {
        let type = UTType(filenameExtension: (name as NSString).pathExtension)
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        return BugSplatAttachment(filename: name, attachmentData: data, contentType: mime)
    }
}

// MARK: - Feedback sheet

struct FeedbackSheet: View {
    /// Which screen the sheet is currently showing.
    private enum Phase {
        case form
        case thanks(BugSplatFeedbackResult?)
    }

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .form

    // Form state — preserved across a failed submit so the user loses nothing.
    @State private var category: FeedbackCategory = .bug
    @State private var title = ""
    @State private var feedbackDescription = ""
    @State private var name = ""
    @State private var email = ""
    @State private var includeLogs = true
    @State private var pickedFile: PickedAttachment?

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showFileImporter = false

    private var database: String {
        BugSplat.shared().bugSplatDatabase ?? "—"
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        Group {
            switch phase {
            case .form:
                formScreen
            case .thanks(let result):
                FeedbackThanksView(result: result, database: database) {
                    dismiss()
                }
            }
        }
        .background(DemoColor.cardBg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Form screen

    private var formScreen: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DemoColor.cardStroke)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    categoryPicker
                    field(label: "Title", required: true) {
                        TextField("", text: $title)
                            .textFieldStyle(.plain)
                            .modifier(FieldBox())
                    }
                    field(label: "Description", required: false) {
                        TextField("", text: $feedbackDescription, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                            .modifier(FieldBox())
                    }
                    field(label: "Name", required: false) {
                        TextField("", text: $name)
                            .textFieldStyle(.plain)
                            .textContentType(.name)
                            .modifier(FieldBox())
                    }
                    field(label: "Email", required: false) {
                        TextField("", text: $email)
                            .textFieldStyle(.plain)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .modifier(FieldBox())
                    }
                    field(label: "Attachment", required: false) {
                        attachmentRow
                    }
                    includeLogsRow
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(DemoColor.asterisk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }

            footer
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            handleFileImport(result)
        }
    }

    private var header: some View {
        HStack {
            Text("Send feedback")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(DemoColor.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DemoColor.textSecondary)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $category) {
            ForEach(FeedbackCategory.allCases) { category in
                Text(category.rawValue).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .disabled(isSubmitting)
    }

    private var attachmentRow: some View {
        Group {
            if let pickedFile {
                HStack(spacing: 12) {
                    Text(pickedFile.typeChip)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DemoColor.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DemoColor.badgeBg))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pickedFile.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DemoColor.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(pickedFile.sizeText)
                            .font(.system(size: 12))
                            .foregroundColor(DemoColor.textTertiary)
                    }
                    Spacer(minLength: 8)
                    Button("Replace") { showFileImporter = true }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DemoColor.link)
                        .disabled(isSubmitting)
                }
                .padding(12)
                .modifier(OutlinedCard())
            } else {
                Button(action: { showFileImporter = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Add attachment")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .foregroundColor(DemoColor.link)
                    .padding(12)
                    .modifier(OutlinedCard())
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
        }
    }

    private var includeLogsRow: some View {
        Toggle(isOn: $includeLogs) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include logs")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DemoColor.textPrimary)
                Text("Attach the app's sample_log.txt")
                    .font(.system(size: 12))
                    .foregroundColor(DemoColor.textTertiary)
            }
        }
        .tint(DemoColor.feedbackAccent)
        .disabled(isSubmitting)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button(action: submit) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Send feedback")
                            .font(.system(size: 17, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSubmit ? DemoColor.feedbackAccent : DemoColor.feedbackAccent.opacity(0.4))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(DemoColor.footerBg.ignoresSafeArea(edges: .bottom))
        .overlay(Divider().overlay(DemoColor.cardStroke), alignment: .top)
    }

    // MARK: Field helper

    @ViewBuilder
    private func field<Content: View>(label: String,
                                      required: Bool,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DemoColor.textPrimary)
                if required {
                    Text("*").font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DemoColor.asterisk)
                }
                Spacer()
                if !required {
                    Text("optional")
                        .font(.system(size: 13))
                        .foregroundColor(DemoColor.textTertiary)
                }
            }
            content()
        }
    }

    // MARK: Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pickedFile = PickedAttachment(name: url.lastPathComponent, data: data)
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't read the selected file: \(error.localizedDescription)"
            }
        case .failure(let error):
            // The system file importer reports user cancellation as a failure on
            // some OS versions; don't surface that as an error message.
            if (error as? CocoaError)?.code == .userCancelled { return }
            errorMessage = "File selection failed: \(error.localizedDescription)"
        }
    }

    private func submit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        var attachments: [BugSplatAttachment] = []
        if let pickedFile { attachments.append(pickedFile.bugSplatAttachment()) }
        if includeLogs, let logAttachment = SampleLog.attachment() {
            attachments.append(logAttachment)
        }

        BugSplat.shared().postFeedback(
            title: trimmedTitle,
            description: feedbackDescription.isEmpty ? nil : feedbackDescription,
            userName: name.isEmpty ? nil : name,
            userEmail: email.isEmpty ? nil : email,
            appKey: nil,
            attributes: ["category": category.rawValue],
            attachments: attachments.isEmpty ? nil : attachments
        ) { result, error in
            DispatchQueue.main.async {
                isSubmitting = false
                if let error {
                    errorMessage = "Feedback failed: \(error.localizedDescription)"
                } else {
                    ActivityLog.record(.feedback, detail: "\u{201C}\(trimmedTitle)\u{201D}")
                    withAnimation { phase = .thanks(result) }
                }
            }
        }
    }
}

// MARK: - Thank-you view

struct FeedbackThanksView: View {
    let result: BugSplatFeedbackResult?
    let database: String
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    private var reportId: String? {
        result?.crashId.map { "\($0)" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(DemoColor.feedbackAccent.opacity(0.14))
                        .frame(width: 84, height: 84)
                    Circle()
                        .stroke(DemoColor.feedbackAccent.opacity(0.35), lineWidth: 1)
                        .frame(width: 84, height: 84)
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(DemoColor.feedbackAccent)
                }

                VStack(spacing: 8) {
                    Text("Feedback sent. Thanks!")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(DemoColor.textPrimary)
                    Text("Your note made it to the BugSplat team. We reply within a day.")
                        .font(.system(size: 15))
                        .foregroundColor(DemoColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                reportIdRow
            }

            Spacer(minLength: 24)

            VStack(spacing: 14) {
                Button(action: openDashboard) {
                    HStack(spacing: 8) {
                        Text("View on dashboard")
                            .font(.system(size: 17, weight: .bold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(DemoColor.feedbackAccent))
                }
                .buttonStyle(.plain)

                Button("Close", action: onClose)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DemoColor.textSecondary)

                poweredByFooter
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(DemoColor.footerBg.ignoresSafeArea(edges: .bottom))
            .overlay(Divider().overlay(DemoColor.cardStroke), alignment: .top)
        }
    }

    private var reportIdRow: some View {
        HStack(spacing: 12) {
            Text("REPORT ID")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.1)
                .foregroundColor(DemoColor.textTertiary)
            Text(reportId ?? "Unavailable")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(DemoColor.textPrimary)
            Spacer(minLength: 8)
            if let reportId {
                Button(action: { UIPasteboard.general.string = reportId }) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Copy").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(DemoColor.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(DemoColor.cardBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(DemoColor.cardStroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(DemoColor.badgeBg))
        .padding(.horizontal, 20)
    }

    private var poweredByFooter: some View {
        HStack(spacing: 4) {
            Text("Powered by")
                .font(.system(size: 13))
                .foregroundColor(DemoColor.textTertiary)
            Link("BugSplat", destination: URL(string: "https://bugsplat.com")!)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DemoColor.link)
        }
        .padding(.top, 2)
    }

    /// Links directly to the report by id. Feedback reports group by their
    /// (unique) title, so the SDK's infoUrl resolves to a generic page — prefer
    /// the id-scoped crash URL, falling back to the database dashboard.
    private func openDashboard() {
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
            openURL(url)
        }
    }
}

// MARK: - Styling helpers

/// Rounded, outlined container used for text fields.
private struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .foregroundColor(DemoColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10).fill(DemoColor.fieldBg))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DemoColor.cardStroke, lineWidth: 1))
    }
}

/// Rounded, outlined container used for the attachment row.
private struct OutlinedCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(DemoColor.fieldBg))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DemoColor.cardStroke, lineWidth: 1))
    }
}

#Preview {
    FeedbackSheet()
}
