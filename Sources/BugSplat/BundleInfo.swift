import Foundation

/// Where `start` gets its defaults from when the caller passes `nil`: the main bundle's
/// Info.plist (`BugSplatDatabase`, `CFBundleDisplayName`/`CFBundleName`,
/// `CFBundleShortVersionString`/`CFBundleVersion`).
protocol InfoDictionaryProviding {
    func object(forInfoDictionaryKey key: String) -> Any?
}

extension Bundle: InfoDictionaryProviding {}

enum BundleInfo {
    /// The Info.plist key that names the BugSplat database.
    static let databaseKey = "BugSplatDatabase"

    struct Resolved: Equatable {
        var database: String
        var application: String
        var version: String
    }

    static func resolve(database: String?, application: String?, version: String?,
                        from info: InfoDictionaryProviding = Bundle.main) throws -> Resolved {
        func plist(_ key: String) -> String? {
            guard let value = info.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let db = nonEmpty(database) ?? plist(databaseKey) else {
            throw BugSplatError(code: .invalidArgument)
        }
        guard let app = nonEmpty(application) ?? plist("CFBundleDisplayName") ?? plist("CFBundleName") else {
            throw BugSplatError(code: .invalidArgument)
        }
        let resolvedVersion: String
        if let explicit = nonEmpty(version) {
            resolvedVersion = explicit
        } else if let short = plist("CFBundleShortVersionString") {
            if let build = plist("CFBundleVersion"), build != short {
                resolvedVersion = "\(short) (\(build))"
            } else {
                resolvedVersion = short
            }
        } else if let build = plist("CFBundleVersion") {
            resolvedVersion = build
        } else {
            throw BugSplatError(code: .invalidArgument)
        }
        return Resolved(database: db, application: app, version: resolvedVersion)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}
