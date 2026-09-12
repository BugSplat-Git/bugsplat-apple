import Foundation
import BugSplatNative

/// BugSplat crash, hang, error and feedback reporting for macOS, iOS and tvOS.
///
/// Call `BugSplat.start(...)` once, as early as possible. On macOS capture, the dialog and the
/// upload all happen out of process (`BugSplatMonitor` and `BugSplatReporter.app`, shipped inside
/// `BugSplatNative.framework`); on iOS and tvOS capture is in process and reports are handled at
/// the next launch. Everything else on this type can be called at any time afterwards, from any
/// thread.
@objc(BugSplat)
public final class BugSplat: NSObject {
    private override init() {}

    /// Version of the loaded native library, e.g. "9.0.0".
    @objc public static var sdkVersion: String { String(cString: bugsplat_version_string()) }

    /// Whether `start` succeeded in this process.
    @objc public static var isStarted: Bool { bugsplat_is_initialized() != 0 }

    /// Receives lifecycle callbacks for the in-app report prompt and uploads the SDK performs
    /// itself (iOS/tvOS, and pending-report drains). The macOS dialog runs out of process and
    /// does not call back.
    @objc public static weak var delegate: BugSplatDelegate?

    // MARK: - Lifecycle

    /// Starts crash reporting. Once per process.
    ///
    /// - Parameters:
    ///   - database: Your BugSplat database. Defaults to the `BugSplatDatabase` Info.plist key.
    ///   - application: Defaults to `CFBundleDisplayName`, then `CFBundleName`.
    ///   - version: Defaults to `CFBundleShortVersionString` (plus ` (CFBundleVersion)` when present).
    ///   - options: See `BugSplat.Options`.
    /// - Throws: `BugSplatError`. `.monitorNotFound` / `.reporterNotFound` mean the framework was
    ///   not embedded with its `Helpers`; there is no degraded in-process mode on macOS.
    public static func start(database: String? = nil,
                             application: String? = nil,
                             version: String? = nil,
                             options: Options = Options()) throws {
        let resolved = try BundleInfo.resolve(database: database, application: application, version: version)
        try start(resolved: resolved, options: options)
    }

    static func start(resolved: BundleInfo.Resolved, options: Options) throws {
        try lock.locked {
            if isStarted { throw BugSplatError(code: .alreadyStarted) }
            logHandler = options.logHandler
            guard let native = options.makeNative(database: resolved.database, application: resolved.application, version: resolved.version) else {
                throw BugSplatError(code: .internalError)
            }
            // bugsplat_init takes ownership of the options, even on failure.
            let result = bugsplat_init(native)
            if let error = BugSplatError(result) {
                logHandler = nil
                throw error
            }
            let state = SessionState(options: options, database: resolved.database, application: resolved.application, version: resolved.version)
            state.key = options.key
            state.user = options.user
            state.email = options.email
            state.userDescription = options.userDescription
            state.notes = options.notes
            state.attributes = options.attributes
            state.attachments = options.attachments
            session = state
        }
        PendingReportDrain.runAfterStart(options: options)
    }

    /// Stops the watchdog and disconnects from the monitor. Rarely needed; the OS reclaims
    /// everything at exit.
    @objc public static func stop() {
        lock.locked {
            bugsplat_shutdown()
            session = nil
            logHandler = nil
        }
    }

    @objc public static func hasCapability(_ capability: Capability) -> Bool {
        bugsplat_has_capability(cenum(capability.rawValue)) != 0
    }

    // MARK: - Report properties (mutable at any time)

    /// Selects the localized support response shown for this crash group.
    @objc public static var key: String? {
        get { session?.key }
        set { setField(newValue, keyPath: \.key, bugsplat_set_key) }
    }

    @objc public static var user: String? {
        get { session?.user }
        set { setField(newValue, keyPath: \.user, bugsplat_set_user) }
    }

    @objc public static var email: String? {
        get { session?.email }
        set { setField(newValue, keyPath: \.email, bugsplat_set_email) }
    }

    /// What the user was doing; shown as the crash description in the dashboard.
    @objc public static var userDescription: String? {
        get { session?.userDescription }
        set { setField(newValue, keyPath: \.userDescription, bugsplat_set_user_description) }
    }

    @objc public static var notes: String? {
        get { session?.notes }
        set { setField(newValue, keyPath: \.notes, bugsplat_set_notes) }
    }

    /// The OS and hardware the app runs on, detected at start ("macOS 15.2 (24C101) arm64",
    /// "iOS 18.2 (22C152) iPhone16,2"). Sent with every report as its own field. Assign to
    /// override; assign `nil` to restore the detected value. `nil` before `start`.
    @objc public static var environment: String? {
        get { bugsplat_get_environment().map { String(cString: $0) } }
        set { _ = bugsplat_set_environment(newValue) }
    }

    /// Custom key/value pairs sent with every report and searchable in the dashboard.
    /// Up to 64; values up to 20 KB.
    public static var attributes: [String: String] { session?.attributes ?? [:] }

    /// Sets or, with `nil`, removes an attribute. Captured at the instant of a crash.
    @objc public static func setAttribute(_ name: String, value: String?) throws {
        try lock.locked {
            try BugSplatError.check(bugsplat_set_attribute(name, value))
            if let value { session?.attributes[name] = value } else { session?.attributes.removeValue(forKey: name) }
        }
    }

    /// Files copied into every report at capture time. Up to 24. Add and remove at any time;
    /// what is in the list when the crash happens is what gets sent.
    public static var attachments: [URL] { session?.attachments ?? [] }

    @objc public static func addAttachment(_ url: URL) throws {
        try lock.locked {
            try BugSplatError.check(bugsplat_add_attachment(url.path))
            if !(session?.attachments.contains(url) ?? true) { session?.attachments.append(url) }
        }
    }

    @objc public static func removeAttachment(_ url: URL) throws {
        try lock.locked {
            try BugSplatError.check(bugsplat_remove_attachment(url.path))
            session?.attachments.removeAll { $0 == url }
        }
    }

    /// Switches the `.dialog` policy to silent uploads for the rest of this session (and back).
    @objc public static var isQuietMode: Bool {
        get { session?.quiet ?? false }
        set { lock.locked { bugsplat_set_quiet_mode(newValue ? 1 : 0); session?.quiet = newValue } }
    }

    // MARK: - Reports that do not end the process

    /// Captures a report of the live process (all threads, like a crash) and keeps running.
    /// Follows the upload policy like a crash would.
    @objc public static func captureReport() throws {
        try BugSplatError.check(bugsplat_capture_report())
    }

    /// Sends user feedback (BugSplat report type 36). Blocks for the upload; use the `async`
    /// variant or the completion-handler variant from UI code.
    public static func postFeedbackSync(title: String, description: String? = nil, attachments: [URL] = []) throws -> UploadResult {
        try withCStringArray(attachments.map(\.path)) { array, count in
            try UploadResult.capture { out in bugsplat_post_feedback(title, description, array, count, out) }
        }
    }

    /// Sends user feedback (BugSplat report type 36).
    public static func postFeedback(title: String, description: String? = nil, attachments: [URL] = []) async throws -> UploadResult {
        try await offMain { try postFeedbackSync(title: title, description: description, attachments: attachments) }
    }

    /// Objective-C friendly feedback. `completion` runs on the main queue.
    @objc public static func postFeedback(title: String, description: String?, attachments: [URL],
                                          completion: @escaping (UploadResultObject?, Error?) -> Void) {
        uploadQueue.async {
            let outcome = Result { try postFeedbackSync(title: title, description: description, attachments: attachments) }
            DispatchQueue.main.async {
                switch outcome {
                case .success(let r): completion(UploadResultObject(r), nil)
                case .failure(let e): completion(nil, e)
                }
            }
        }
    }

    /// Posts an AddressSanitizer text report (type 25).
    public static func postASanReport(_ text: String) async throws -> UploadResult {
        try await offMain { try UploadResult.capture { out in bugsplat_post_asan_report(text, out) } }
    }

    // MARK: - Hang detection

    /// Tells the watchdog the caller is alive. Needed only for processes without a main run loop
    /// (the SDK pings the main dispatch queue itself) and for threads registered with `watchThread`.
    @objc public static func heartbeat() {
        bugsplat_heartbeat()
    }

    /// Watches the calling thread in addition to the main thread; `name` appears in the hang
    /// report. Throws `.unsupported` when hang detection was not enabled in the options.
    @objc public static func watchThread(name: String) throws {
        try BugSplatError.check(bugsplat_watch_thread(name))
    }

    @objc public static func unwatchThread() {
        bugsplat_unwatch_thread()
    }

    // MARK: - Pending reports

    /// Reports in the store that nobody is uploading: everything left by a previous session on
    /// iOS/tvOS, and reports stored under the `.manual` policy on every platform.
    public static func pendingReports() -> [PendingReport] {
        guard let list = bugsplat_pending_reports() else { return [] }
        defer { bugsplat_report_list_free(list) }
        var reports: [PendingReport] = []
        for i in 0..<bugsplat_report_list_count(list) {
            guard let folder = bugsplat_report_list_folder(list, i), let json = bugsplat_report_list_json(list, i) else { continue }
            if let report = PendingReport(folder: String(cString: folder), json: String(cString: json)) {
                reports.append(report)
            }
        }
        return reports
    }

    /// Uploads one pending report, optionally overriding the stored user, email and description.
    public static func send(_ report: PendingReport, user: String? = nil, email: String? = nil, description: String? = nil) async throws -> UploadResult {
        try await offMain { try sendSync(report, user: user, email: email, description: description) }
    }

    public static func sendSync(_ report: PendingReport, user: String? = nil, email: String? = nil, description: String? = nil) throws -> UploadResult {
        let result = try UploadResult.capture { out in
            bugsplat_send_report(report.folder.path, user, email, description, out)
        }
        notifyDelegate { $0.bugSplatDidSendReport?(crashId: result.crashId, infoURL: result.infoURL, folder: report.folder) }
        return result
    }

    /// Deletes a pending report without sending it.
    public static func discard(_ report: PendingReport) throws {
        try BugSplatError.check(bugsplat_discard_report(report.folder.path))
    }

    /// Uploads every pending report from previous sessions in the background, silently.
    @objc public static func postPendingReports() throws {
        try BugSplatError.check(bugsplat_post_pending_reports_async())
    }

    // MARK: - Diagnostics

    /// `BugSplat.log` inside the store; the first place to look when something is off.
    @objc public static var logFileURL: URL? {
        bugsplat_log_file_path().map { URL(fileURLWithPath: String(cString: $0)) }
    }

    /// Where reports are kept until uploaded.
    @objc public static var storeDirectory: URL? {
        logFileURL?.deletingLastPathComponent()
    }

    // MARK: - Internals

    final class SessionState {
        let options: Options
        let database: String
        let application: String
        let version: String
        var key: String?
        var user: String?
        var email: String?
        var userDescription: String?
        var notes: String?
        var attributes: [String: String] = [:]
        var attachments: [URL] = []
        var quiet: Bool

        init(options: Options, database: String, application: String, version: String) {
            self.options = options
            self.database = database
            self.application = application
            self.version = version
            self.quiet = options.uploadPolicy == .quiet
        }
    }

    static let lock = NSLock()
    nonisolated(unsafe) static var session: SessionState?
    nonisolated(unsafe) static var logHandler: ((LogLevel, String) -> Void)?
    static let uploadQueue = DispatchQueue(label: "com.bugsplat.upload", qos: .utility)

    static let nativeLogCallback: bugsplat_log_fn = { level, message, _ in
        guard let handler = BugSplat.logHandler, let message else { return }
        handler(LogLevel(rawValue: Int(level.rawValue)) ?? .info, String(cString: message))
    }

    private static func setField(_ value: String?, keyPath: ReferenceWritableKeyPath<SessionState, String?>,
                                 _ setter: (UnsafePointer<CChar>?) -> bugsplat_result) {
        lock.locked {
            _ = setter(value)
            session?[keyPath: keyPath] = value
        }
    }

    static func notifyDelegate(_ body: @escaping (BugSplatDelegate) -> Void) {
        guard let delegate else { return }
        if Thread.isMainThread { body(delegate) } else { DispatchQueue.main.async { body(delegate) } }
    }

    /// Runs blocking C work off the caller's thread (uploads take seconds).
    static func offMain<T: Sendable>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            uploadQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    static func withCStringArray<T>(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>?, Int) throws -> T) rethrows -> T {
        if strings.isEmpty { return try body(nil, 0) }
        var pointers: [UnsafePointer<CChar>?] = strings.map { UnsafePointer(strdup($0)) }
        defer { pointers.forEach { if let p = $0 { free(UnsafeMutablePointer(mutating: p)) } } }
        return try pointers.withUnsafeBufferPointer { try body($0.baseAddress, strings.count) }
    }
}

extension NSLock {
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
