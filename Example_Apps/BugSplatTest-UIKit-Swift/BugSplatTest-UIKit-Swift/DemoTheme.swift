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
    static let textSecondary = UIColor(hex: 0x6B7280)
    static let textTertiary = UIColor(hex: 0x9CA3AF)
    static let badgeBg      = UIColor(hex: 0xF1EFE8)
    static let pillStroke   = UIColor(hex: 0xE4E2DA)
    static let connectedDot = UIColor(hex: 0x22C55E)
    static let link         = UIColor(hex: 0x1F73E8)

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
