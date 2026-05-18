//
//  ActivityLog.swift
//  BugSplatTest-UIKit-Swift
//
//  Local persistence of user-triggered demo events. Mirrors the Android sample's
//  ActivityLog so the demo UIs stay consistent across platforms.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import Foundation

enum ActivityType: String, Codable {
    case crash, error, feedback, hang
}

struct ActivityEntry: Codable, Identifiable {
    let type: ActivityType
    let detail: String
    let timestamp: Date

    var id: String { "\(timestamp.timeIntervalSince1970)-\(type.rawValue)-\(detail)" }
}

enum ActivityLog {
    private static let key = "bugsplat.example.activity.entries"
    private static let maxEntries = 10

    /// Append a new entry (becomes the newest) and persist. Crash and hang
    /// entries are flushed synchronously so the row survives the impending
    /// process death (crash) or force-quit (hang).
    static func record(_ type: ActivityType, detail: String) {
        var entries = all()
        entries.insert(ActivityEntry(type: type, detail: detail, timestamp: Date()), at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
        if type == .crash || type == .hang {
            // Best-effort sync flush. synchronize() is deprecated but still the
            // closest analog to Android's SharedPreferences.commit() and the
            // only way to guarantee persistence before SIGKILL.
            UserDefaults.standard.synchronize()
        }
    }

    static func all() -> [ActivityEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ActivityEntry].self, from: data)) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Relative-time formatting matched to the Android strings: `just now`, `Xm ago`,
/// `Xh ago`, `Xd ago`.
enum RelativeTime {
    static func string(from then: Date, to now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(then))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
