import Foundation
import BugSplatNative

/// Every failure the SDK reports. Wraps `bugsplat_result` from the C ABI and bridges to
/// `NSError` (domain `com.bugsplat.BugSplat`, code = `Code.rawValue`) for Objective-C callers.
public struct BugSplatError: Error, Equatable, Hashable, CustomStringConvertible, CustomNSError, LocalizedError, Sendable {
    /// Stable across ABI version 1; values match `bugsplat_result`.
    public enum Code: Int, Sendable, CaseIterable {
        case invalidArgument = 1
        /// `BugSplat.start` was already called in this process.
        case alreadyStarted = 2
        case notStarted = 3
        /// `BugSplatMonitor` is missing from the framework's `Helpers` directory. This is a
        /// packaging error; there is no in-process fallback.
        case monitorNotFound = 4
        case monitorStartFailed = 5
        /// `BugSplatReporter.app` is missing from the framework's `Helpers` directory (macOS).
        case reporterNotFound = 6
        case io = 7
        /// 24 attachments, 64 attributes, 20 KB per value.
        case limitExceeded = 8
        /// Not available on this platform or backend.
        case unsupported = 9
        case network = 10
        /// See `httpStatus`.
        case http = 11
        /// The server refused the report (size limit, throttling).
        case rejected = 12
        /// The user chose not to send.
        case cancelled = 13
        case internalError = 14
    }

    public let code: Code
    /// Last HTTP status of the upload that failed, 0 when none.
    public let httpStatus: Int

    public init(code: Code, httpStatus: Int = 0) {
        self.code = code
        self.httpStatus = httpStatus
    }

    /// `nil` when `result` is `BUGSPLAT_OK`.
    init?(_ result: bugsplat_result, httpStatus: Int32 = 0) {
        guard result != BUGSPLAT_OK else { return nil }
        self.code = Code(rawValue: Int(result.rawValue)) ?? .internalError
        self.httpStatus = Int(httpStatus)
    }

    static func check(_ result: bugsplat_result) throws {
        if let error = BugSplatError(result) { throw error }
    }

    // MARK: CustomNSError

    public static var errorDomain: String { "com.bugsplat.BugSplat" }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [NSLocalizedDescriptionKey: description]
        if httpStatus != 0 { info["httpStatus"] = httpStatus }
        return info
    }

    // MARK: LocalizedError

    public var errorDescription: String? { description }

    public var description: String {
        let base: String
        switch code {
        case .invalidArgument: base = "Invalid argument"
        case .alreadyStarted: base = "BugSplat was already started in this process"
        case .notStarted: base = "BugSplat.start has not been called"
        case .monitorNotFound: base = "BugSplatMonitor was not found in the framework's Helpers directory (packaging error)"
        case .monitorStartFailed: base = "BugSplatMonitor could not be started"
        case .reporterNotFound: base = "BugSplatReporter.app was not found in the framework's Helpers directory (packaging error)"
        case .io: base = "I/O error in the BugSplat report store"
        case .limitExceeded: base = "Limit exceeded (24 attachments, 64 attributes, 20 KB per value)"
        case .unsupported: base = "Not supported on this platform"
        case .network: base = "Network error while uploading the report"
        case .http: base = "The server returned an error"
        case .rejected: base = "The server rejected the report (size limit or throttling)"
        case .cancelled: base = "The user chose not to send the report"
        case .internalError: base = "Internal BugSplat error"
        }
        return httpStatus != 0 ? "\(base) (HTTP \(httpStatus))" : base
    }
}
