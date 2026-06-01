//
//  DemoComponents.swift
//  BugSplatTest-SwiftUI
//
//  Reusable views for the demo screen: top-bar pill, database badge, event
//  card, and recent-activity row.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI

struct StatusPill: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DemoColor.connectedDot)
                .frame(width: 8, height: 8)
                .opacity(connected ? 1 : 0.35)
            Text(connected ? "Connected" : "Offline")
                .font(.system(size: 12))
                .foregroundColor(DemoColor.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.white)
        )
        .overlay(
            Capsule().stroke(DemoColor.pillStroke, lineWidth: 1)
        )
    }
}

struct DatabaseBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(DemoColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(DemoColor.badgeBg)
            )
    }
}

struct EventCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(DemoColor.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(DemoColor.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(DemoColor.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(DemoColor.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RecentActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .padding(.trailing, 12)
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DemoColor.textPrimary)
                .padding(.trailing, 14)
            Text(entry.detail)
                .font(.system(size: 14))
                .foregroundColor(DemoColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 10)
            Text(RelativeTime.string(from: entry.timestamp))
                .font(.system(size: 13))
                .foregroundColor(DemoColor.textTertiary)
        }
    }

    private var dotColor: Color {
        switch entry.type {
        case .crash:    return DemoColor.activityCrash
        case .error:    return DemoColor.activityError
        case .feedback: return DemoColor.activityFeedback
        case .hang:     return DemoColor.activityHang
        }
    }

    private var label: String {
        switch entry.type {
        case .crash:    return "Crash"
        case .error:    return "Error"
        case .feedback: return "Feedback"
        case .hang:     return "Hang"
        }
    }
}
