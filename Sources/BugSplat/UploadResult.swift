import Foundation
import BugSplatNative

/// What the server said about an uploaded report.
public struct UploadResult: Equatable, Hashable, Sendable {
    /// The BugSplat report id; 0 while the report is still pending (MANUAL policy).
    public let crashId: Int64
    /// 0 while the server is still processing the report.
    public let stackKeyId: Int64
    /// Last HTTP status of the upload, 0 if none.
    public let httpStatus: Int
    /// The support-response page for this report, when one is configured.
    public let infoURL: URL?

    /// `true` when the report was stored but not uploaded because the policy is `.manual`.
    public var isDeferred: Bool { crashId == 0 }

    public init(crashId: Int64, stackKeyId: Int64 = 0, httpStatus: Int = 0, infoURL: URL? = nil) {
        self.crashId = crashId
        self.stackKeyId = stackKeyId
        self.httpStatus = httpStatus
        self.infoURL = infoURL
    }

    /// Runs a C call that fills a `bugsplat_upload_result`, frees `info_url`, and maps errors.
    static func capture(_ body: (UnsafeMutablePointer<bugsplat_upload_result>) -> bugsplat_result) throws -> UploadResult {
        var out = bugsplat_upload_result()
        out.struct_size = UInt32(MemoryLayout<bugsplat_upload_result>.size)
        defer { bugsplat_upload_result_free(&out) }
        let result = body(&out)
        if let error = BugSplatError(result, httpStatus: out.http_status) { throw error }
        let info = out.info_url.map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        return UploadResult(crashId: out.crash_id, stackKeyId: out.stack_key_id, httpStatus: Int(out.http_status), infoURL: info)
    }
}

/// `UploadResult` for Objective-C completion handlers.
@objc(BugSplatUploadResult)
public final class UploadResultObject: NSObject {
    @objc public let crashId: Int64
    @objc public let stackKeyId: Int64
    @objc public let httpStatus: Int
    @objc public let infoURL: URL?
    @objc public var isDeferred: Bool { crashId == 0 }

    public init(_ result: UploadResult) {
        crashId = result.crashId
        stackKeyId = result.stackKeyId
        httpStatus = result.httpStatus
        infoURL = result.infoURL
    }

    public var value: UploadResult { UploadResult(crashId: crashId, stackKeyId: stackKeyId, httpStatus: httpStatus, infoURL: infoURL) }
}
