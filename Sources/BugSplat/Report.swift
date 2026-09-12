import Foundation
import BugSplatNative

extension BugSplat {
    /// A structured report you build yourself: for caught errors, script runtimes, engines and
    /// managed code. Serialized to BugSplat's XML report schema or its JSON mirror and posted
    /// through the same store and uploader as a crash (report type 21).
    public final class Report {
        private var handle: OpaquePointer?

        public init(format: ReportFormat = .json) {
            handle = bugsplat_report_new(cenum(format.rawValue))
        }

        deinit {
            if let handle { bugsplat_report_free(handle) }
        }

        /// Defaults to the running platform and OS; set to describe another runtime.
        public func setPlatform(_ platform: String, os: String) {
            bugsplat_report_set_platform(handle, platform, os)
        }

        public func setException(code: String, explanation: String) {
            bugsplat_report_set_exception(handle, code, explanation)
        }

        public func addModule(name: String, path: String? = nil, baseAddress: UInt64 = 0, size: UInt64 = 0,
                              fileVersion: String? = nil, productVersion: String? = nil) {
            bugsplat_report_add_module(handle, name, path, baseAddress, size, fileVersion, productVersion)
        }

        /// Returns the thread index to pass to `addFrame`.
        @discardableResult
        public func addThread(id: String, isCrashing: Bool) -> Int32 {
            bugsplat_report_add_thread(handle, id, isCrashing ? 1 : 0)
        }

        public func addFrame(thread: Int32, function: String?, file: String? = nil, line: Int32 = 0,
                             module: String? = nil, address: UInt64 = 0) {
            bugsplat_report_add_frame(handle, thread, function, file, line, module, address)
        }

        public func addRegister(name: String, value: String) {
            bugsplat_report_add_register(handle, name, value)
        }

        public func addAttachment(_ url: URL) {
            bugsplat_report_add_attachment(handle, url.path)
        }

        /// Stores and uploads the report according to the upload policy (blocking). The report
        /// cannot be posted twice.
        public func postSync() throws -> UploadResult {
            guard let h = handle else { throw BugSplatError(code: .invalidArgument) }
            handle = nil
            defer { bugsplat_report_free(h) }
            return try UploadResult.capture { out in bugsplat_report_post(h, out) }
        }

        public func post() async throws -> UploadResult {
            try await BugSplat.offMain { try self.postSync() }
        }
    }
}

// MARK: - Convenience constructors

extension BugSplat.Report {
    /// A report for a caught Swift `Error`, with the current thread's call stack.
    public convenience init(error: Error, format: ReportFormat = .json, callStack: [String] = Thread.callStackSymbols) {
        self.init(format: format)
        let nsError = error as NSError
        let code = nsError.domain.isEmpty ? String(reflecting: type(of: error)) : "\(nsError.domain) \(nsError.code)"
        setException(code: code, explanation: error.localizedDescription)
        addCallStack(callStack, threadName: Thread.isMainThread ? "main" : (Thread.current.name ?? "thread"))
    }

    /// A report for an `NSException` caught in Objective-C code.
    public convenience init(exception: NSException, format: ReportFormat = .json) {
        self.init(format: format)
        setException(code: exception.name.rawValue, explanation: exception.reason ?? exception.name.rawValue)
        addCallStack(exception.callStackSymbols, threadName: "main")
    }

    /// Adds `Thread.callStackSymbols`-style lines as the crashing thread. Frames from this
    /// framework itself are dropped so the top frame is the caller's.
    public func addCallStack(_ symbols: [String], threadName: String = "main") {
        let frames = CallStackSymbols.parse(symbols)
        let thread = addThread(id: threadName, isCrashing: true)
        var seenCaller = false
        var modules = Set<String>()
        for frame in frames {
            if !seenCaller && frame.module == "BugSplat" { continue }
            seenCaller = true
            addFrame(thread: thread, function: frame.symbol, module: frame.module, address: frame.address)
            if modules.insert(frame.module).inserted { addModule(name: frame.module) }
        }
    }
}

extension BugSplat {
    /// Posts a caught error as a structured report. Convenience for
    /// `BugSplat.Report(error:).post()`.
    public static func post(_ error: Error, format: ReportFormat = .json) async throws -> UploadResult {
        let report = Report(error: error, format: format)
        return try await report.post()
    }
}
