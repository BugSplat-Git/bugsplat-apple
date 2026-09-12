import Foundation
import BugSplatNative

/// What happens to a report once it exists in the store.
@objc(BugSplatUploadPolicy)
public enum UploadPolicy: Int, Sendable {
    /// macOS: `BugSplatReporter.app` shows the BugSplat dialog out of process, then uploads.
    /// iOS/tvOS: the user is asked at the next launch with an in-app prompt.
    case dialog = 0
    /// Upload without any UI.
    case quiet = 1
    /// Leave reports pending; the app drains them with `BugSplat.pendingReports()`.
    case manual = 2
}

/// How much of the process memory a crash dump carries. Size is enforced server-side at upload
/// time; there is no client-side gate. Not available on iOS/tvOS.
@objc(BugSplatDumpType)
public enum DumpType: Int, Sendable {
    /// Threads, stacks, modules, exception (Crashpad default).
    case normal = 0
    /// Plus private writable memory (heaps).
    case heap = 1
    /// Every readable region.
    case full = 2
}

/// What the watchdog does once the main thread (or a watched thread) stops answering.
@objc(BugSplatHangPolicy)
public enum HangPolicy: Int, Sendable {
    /// Non-fatal: dump the live process out of process, report it, keep running.
    case report = 0
    /// Fatal: report, offer Wait / Close in the dialog, terminate on Close.
    case reportAndTerminate = 1
}

/// Serialization of a structured (client-built) report.
@objc(BugSplatReportFormat)
public enum ReportFormat: Int, Sendable {
    /// BugSplat's existing `bsCrashReport.xml` schema.
    case xml = 0
    /// A 1:1 JSON mirror of the XML schema.
    case json = 1
}

@objc(BugSplatLogLevel)
public enum LogLevel: Int, Sendable {
    case debug = 0, info = 1, warning = 2, error = 3
}

/// Capability queries; answers depend on platform and configuration.
@objc(BugSplatCapability)
public enum Capability: Int, Sendable {
    case outOfProcess = 1
    /// Windows only.
    case wer = 2
    case hangDetection = 3
    case crashDialog = 4
    /// Never on Apple platforms.
    case onCrashCallback = 5
    /// Desktop only.
    case fullMemoryDump = 6
    case dynamicAttachments = 7
    case crashSignature = 8
}

extension BugSplat {
    /// Main-thread (and watched-thread) hang detection. The SDK pings the main dispatch queue
    /// itself; apps without a main run loop call `BugSplat.heartbeat()` at least once per timeout.
    public struct HangDetection: Equatable, Sendable {
        public var timeout: TimeInterval
        public var policy: HangPolicy

        public init(timeout: TimeInterval = 5, policy: HangPolicy = .report) {
            self.timeout = timeout
            self.policy = policy
        }
    }

    /// Everything `BugSplat.start` needs beyond the database, application and version. All of the
    /// report properties (`user`, `email`, `attributes`, `attachments`, ...) are only initial
    /// values: each can be changed at any time after `start` through the `BugSplat` statics.
    public struct Options {
        public var uploadPolicy: UploadPolicy = .dialog
        public var dumpType: DumpType = .normal
        /// `nil` disables hang detection.
        public var hangDetection: HangDetection? = nil
        /// Where reports are kept until uploaded. Default:
        /// `~/Library/Application Support/BugSplat/<application>-<version>/` (inside the
        /// container for sandboxed apps).
        public var storeDirectory: URL? = nil
        /// Override the `BugSplatMonitor` location (normally found inside the framework).
        public var monitorURL: URL? = nil
        /// Override the `BugSplatReporter.app` location (macOS; normally found inside the framework).
        public var reporterURL: URL? = nil
        /// A `theme/` directory for the macOS dialog (theme.json + strings); overrides the one
        /// shipped inside the framework.
        public var themeDirectory: URL? = nil
        /// Open the support-response URL after an interactive upload. `nil` = platform default
        /// (on for macOS, off for iOS/tvOS).
        public var openSupportURL: Bool? = nil
        /// Compute the crash signature and hash on the client before upload. Default on.
        public var crashSignature: Bool = true
        /// Hosts with their own signal handlers: defer to the previous handler first.
        public var chainPreviousHandlers: Bool = false
        /// Override the server crash type. `nil` = the platform's default (5, Crashpad minidump).
        public var crashTypeId: Int32? = nil
        /// iOS/tvOS only: show the in-app "send report?" prompt for reports left over from a
        /// previous session when the policy is `.dialog`. Default on.
        public var promptForPendingReports: Bool = true

        // Initial report properties, all mutable later.
        public var key: String? = nil
        public var user: String? = nil
        public var email: String? = nil
        public var userDescription: String? = nil
        public var notes: String? = nil
        /// Overrides the auto-detected OS/hardware summary ("macOS 15.2 (24C101) arm64").
        public var environment: String? = nil
        public var attributes: [String: String] = [:]
        public var attachments: [URL] = []

        /// Receives the SDK's own log lines (also written to `BugSplat.log` in the store).
        public var logHandler: ((LogLevel, String) -> Void)? = nil

        public init() {}
    }
}

// MARK: - C interop

/// Builds a `bugsplat_options` for the C ABI. Imported C enums are structs whose raw value
/// type depends on the importer, hence the generic conversion.
func cenum<T: RawRepresentable>(_ value: Int) -> T where T.RawValue: FixedWidthInteger {
    T(rawValue: T.RawValue(value))!
}

extension BugSplat.Options {
    func makeNative(database: String, application: String, version: String) -> OpaquePointer? {
        guard let o = bugsplat_options_new(database, application, version) else { return nil }
        bugsplat_options_set_upload_policy(o, cenum(uploadPolicy.rawValue))
        bugsplat_options_set_dump_type(o, cenum(dumpType.rawValue))
        if let hang = hangDetection {
            bugsplat_options_set_hang_detection(o, Int32((hang.timeout * 1000).rounded()), cenum(hang.policy.rawValue))
        }
        if let dir = storeDirectory { bugsplat_options_set_store_dir(o, dir.path) }
        if let url = monitorURL { bugsplat_options_set_monitor_path(o, url.path) }
        if let url = reporterURL { bugsplat_options_set_reporter_path(o, url.path) }
        if let dir = themeDirectory { bugsplat_options_set_theme_dir(o, dir.path) }
        if let open = openSupportURL { bugsplat_options_set_open_support_url(o, open ? 1 : 0) }
        bugsplat_options_set_crash_signature(o, crashSignature ? 1 : 0)
        bugsplat_options_set_chain_previous_signal_handlers(o, chainPreviousHandlers ? 1 : 0)
        if let id = crashTypeId { bugsplat_options_set_crash_type_id(o, id) }
        if let v = key { bugsplat_options_set_key(o, v) }
        if let v = user { bugsplat_options_set_user(o, v) }
        if let v = email { bugsplat_options_set_email(o, v) }
        if let v = userDescription { bugsplat_options_set_user_description(o, v) }
        if let v = notes { bugsplat_options_set_notes(o, v) }
        if let v = environment { bugsplat_options_set_environment(o, v) }
        for (name, value) in attributes.sorted(by: { $0.key < $1.key }) {
            bugsplat_options_set_attribute(o, name, value)
        }
        for url in attachments { bugsplat_options_add_attachment(o, url.path) }
        if logHandler != nil {
            bugsplat_options_set_logger(o, BugSplat.nativeLogCallback, nil)
        }
        return o
    }
}
