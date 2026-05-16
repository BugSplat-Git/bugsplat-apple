//
//  DemoTheme.swift
//  BugSplatTest-SwiftUI
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI

enum DemoColor {
    static let screenBg     = Color(hex: 0xFAF8F2)
    static let cardBg       = Color(hex: 0xFFFFFF)
    static let cardStroke   = Color(hex: 0xECEAE2)
    static let textPrimary  = Color(hex: 0x0E1116)
    static let textSecondary = Color(hex: 0x6B7280)
    static let textTertiary = Color(hex: 0x9CA3AF)
    static let badgeBg      = Color(hex: 0xF1EFE8)
    static let pillStroke   = Color(hex: 0xE4E2DA)
    static let connectedDot = Color(hex: 0x22C55E)
    static let link         = Color(hex: 0x1F73E8)

    static let activityCrash    = Color(hex: 0x1F73E8)
    static let activityError    = Color(hex: 0xE5B142)
    static let activityFeedback = Color(hex: 0x22C55E)
    static let activityHang     = Color(hex: 0xE5B142) // reuse error per spec
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
