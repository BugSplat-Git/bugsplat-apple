//
//  DemoTheme.swift
//  BugSplatTest-UIKit-Swift
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import UIKit

enum DemoColor {
    static let screenBg     = UIColor(hex: 0xFAF8F2)
    static let cardBg       = UIColor(hex: 0xFFFFFF)
    static let cardStroke   = UIColor(hex: 0xECEAE2)
    static let textPrimary  = UIColor(hex: 0x0E1116)
    // Both secondary and tertiary clear WCAG AA (≥4.5:1) against the card and
    // screen backgrounds. Tertiary used to be a lighter gray (#9CA3AF, ~2.5:1)
    // but small section headers and footers became hard to read.
    static let textSecondary = UIColor(hex: 0x4B5563)
    static let textTertiary = UIColor(hex: 0x6B7280)
    static let badgeBg      = UIColor(hex: 0xF1EFE8)
    static let pillStroke   = UIColor(hex: 0xE4E2DA)
    static let connectedDot = UIColor(hex: 0x22C55E)
    static let link         = UIColor(hex: 0x1F73E8)
    // Primary action green used by the feedback sheet (form + thank-you buttons).
    static let feedbackAccent = UIColor(hex: 0x4E9D78)
    static let footerBg     = UIColor(hex: 0xF4F2EA)
    static let asterisk     = UIColor(hex: 0xDC2626)

    static let activityCrash    = UIColor(hex: 0x1F73E8)
    static let activityError    = UIColor(hex: 0xE5B142)
    static let activityFeedback = UIColor(hex: 0x22C55E)
    static let activityHang     = UIColor(hex: 0xE5B142) // reuse error per spec
}

extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8)  & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
