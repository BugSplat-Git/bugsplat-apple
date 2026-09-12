import Foundation

/// `BugSplat.Options` for Objective-C callers. Every property mirrors the Swift struct.
@objc(BugSplatConfiguration)
public final class BugSplatConfiguration: NSObject {
    @objc public var uploadPolicy: UploadPolicy = .dialog
    @objc public var dumpType: DumpType = .normal
    /// Seconds; 0 disables hang detection.
    @objc public var hangTimeout: TimeInterval = 0
    @objc public var hangPolicy: HangPolicy = .report
    @objc public var storeDirectory: URL?
    @objc public var monitorURL: URL?
    @objc public var reporterURL: URL?
    @objc public var themeDirectory: URL?
    /// `nil` = platform default.
    @objc public var openSupportURL: NSNumber?
    @objc public var crashSignature = true
    @objc public var chainPreviousHandlers = false
    /// 0 = platform default.
    @objc public var crashTypeId: Int32 = 0
    @objc public var promptForPendingReports = true
    @objc public var key: String?
    @objc public var user: String?
    @objc public var email: String?
    @objc public var userDescription: String?
    @objc public var notes: String?
    @objc public var environment: String?
    @objc public var attributes: [String: String] = [:]
    @objc public var attachments: [URL] = []
    @objc public var logHandler: ((LogLevel, String) -> Void)?

    public var options: BugSplat.Options {
        var o = BugSplat.Options()
        o.uploadPolicy = uploadPolicy
        o.dumpType = dumpType
        o.hangDetection = hangTimeout > 0 ? BugSplat.HangDetection(timeout: hangTimeout, policy: hangPolicy) : nil
        o.storeDirectory = storeDirectory
        o.monitorURL = monitorURL
        o.reporterURL = reporterURL
        o.themeDirectory = themeDirectory
        o.openSupportURL = openSupportURL?.boolValue
        o.crashSignature = crashSignature
        o.chainPreviousHandlers = chainPreviousHandlers
        o.crashTypeId = crashTypeId != 0 ? crashTypeId : nil
        o.promptForPendingReports = promptForPendingReports
        o.key = key
        o.user = user
        o.email = email
        o.userDescription = userDescription
        o.notes = notes
        o.environment = environment
        o.attributes = attributes
        o.attachments = attachments
        o.logHandler = logHandler
        return o
    }
}

extension BugSplat {
    /// Objective-C entry point: `[BugSplat startWithDatabase:application:version:configuration:error:]`.
    /// Pass `nil` for any value that should come from Info.plist.
    @objc public static func start(database: String?, application: String?, version: String?,
                                   configuration: BugSplatConfiguration?) throws {
        try start(database: database, application: application, version: version,
                  options: configuration?.options ?? Options())
    }

    /// `BugSplat.attributes` for Objective-C.
    @objc public static var attributeDictionary: [String: String] { attributes }

    /// `BugSplat.attachments` for Objective-C.
    @objc public static var attachmentURLs: [URL] { attachments }

    /// `BugSplat.pendingReports()` folders for Objective-C; send them with `sendPendingReport(folder:...)`.
    @objc public static var pendingReportFolders: [URL] { pendingReports().map(\.folder) }

    @objc public static func sendPendingReport(folder: URL, user: String?, email: String?, description: String?,
                                               completion: @escaping (UploadResultObject?, Error?) -> Void) {
        guard let report = pendingReports().first(where: { $0.folder.standardizedFileURL == folder.standardizedFileURL }) else {
            DispatchQueue.main.async { completion(nil, BugSplatError(code: .invalidArgument)) }
            return
        }
        uploadQueue.async {
            let outcome = Result { try sendSync(report, user: user, email: email, description: description) }
            DispatchQueue.main.async {
                switch outcome {
                case .success(let r): completion(UploadResultObject(r), nil)
                case .failure(let e): completion(nil, e)
                }
            }
        }
    }

    @objc public static func discardPendingReport(folder: URL) throws {
        guard let report = pendingReports().first(where: { $0.folder.standardizedFileURL == folder.standardizedFileURL }) else {
            throw BugSplatError(code: .invalidArgument)
        }
        try discard(report)
    }
}
