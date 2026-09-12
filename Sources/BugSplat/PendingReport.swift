import Foundation

/// A report waiting in the store (`BugSplatCrashData.json`, schema 2), as returned by
/// `BugSplat.pendingReports()`.
public struct PendingReport: Identifiable, Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case crash, hang, capture, structured, feedback, unknown
    }

    /// The report folder inside the store; also the report's identity.
    public let folder: URL
    public var id: String { folder.lastPathComponent }

    public let kind: Kind
    public let database: String
    public let application: String
    public let version: String
    public let crashTime: Date?
    public let environment: String?
    public let user: String?
    public let email: String?
    public let userDescription: String?
    public let signalOrExceptionCode: String?
    /// Only for hang reports.
    public let hangDuration: TimeInterval?
    public let attributes: [String: String]
    /// File names inside the folder.
    public let attachments: [String]
    /// `dialog`, `quiet` or `manual`, as recorded when the report was captured.
    public let uploadPolicy: String
    /// How many upload attempts failed with a retryable status.
    public let retryCount: Int
    /// The raw `BugSplatCrashData.json`.
    public let json: String

    /// Parses a `BugSplatCrashData.json`; tolerant of missing keys, `nil` only when the text is
    /// not a JSON object at all.
    public init?(folder: String, json: String) {
        guard let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        self.folder = URL(fileURLWithPath: folder, isDirectory: true)
        self.json = json
        func string(_ key: String) -> String? {
            guard let s = object[key] as? String, !s.isEmpty else { return nil }
            return s
        }
        kind = Kind(rawValue: string("reportKind") ?? "") ?? .unknown
        database = string("database") ?? ""
        application = string("appName") ?? ""
        version = string("appVersion") ?? ""
        crashTime = string("crashTime").flatMap(PendingReport.parseTime)
        environment = string("environment")
        user = string("user")
        email = string("email")
        userDescription = string("userDescription")
        signalOrExceptionCode = string("signalOrExceptionCode")
        if let ms = object["hangDurationMs"] as? NSNumber, ms.doubleValue > 0 {
            hangDuration = ms.doubleValue / 1000
        } else {
            hangDuration = nil
        }
        attributes = (object["attributes"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
        attachments = (object["attachments"] as? [Any])?.compactMap { $0 as? String } ?? []
        uploadPolicy = string("uploadPolicy") ?? "dialog"
        retryCount = (object["retryCount"] as? NSNumber)?.intValue ?? 0
    }

    private static let timeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseTime(_ text: String) -> Date? {
        timeFormatter.date(from: text)
    }
}
