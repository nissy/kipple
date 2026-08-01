//
//  MainViewMetrics.swift
//  Kipple
//
//  Created by Codex on 2025/11/03.
//

import SwiftUI

enum MainViewMetrics {
    enum TextColor {
        static let primary = Color(.sRGB, red: 0.2, green: 0.2, blue: 0.2, opacity: 1)
        static let primaryNSColor = NSColor(calibratedWhite: 0.2, alpha: 1)
    }

    enum TitleBar {
        static let buttonSize: CGFloat = KippleButtonMetrics.toolbarSize
        static let iconFont: Font = .system(size: 12, weight: .medium)
        static let badgeFont: Font = .system(size: 11, weight: .bold)
        static let badgeOffset = CGSize(width: -2, height: 2)
    }
    
    enum BottomBar {
        static let buttonSize: CGFloat = KippleButtonMetrics.toolbarSize
        static let iconFont: Font = .system(size: 12, weight: .medium)
        static let clearIconFont: Font = .system(size: 12)
    }

    enum HistoryFilterMenu {
        static let iconFont: Font = .system(size: 12, weight: .regular)
        static let labelFont: Font = .system(size: 12)
        static let checkmarkFont: Font = .system(size: 12, weight: .semibold)
    }

    enum HistorySearchField {
        static let iconFont: Font = .system(size: 11, weight: .medium)
        static let clearIconFont: Font = .system(size: 11)
        static let height: CGFloat = 32
    }

    enum HistoryColumns {
        static let sectionHorizontalPadding: CGFloat = 10
        static let horizontalInset: CGFloat = 6
        static let spacing: CGFloat = 5
        static let toolbarSpacing: CGFloat = spacing
        static let toolbarTopPadding: CGFloat = 0
        static let toolbarBottomPadding: CGFloat = 6
        static let controlColumnWidth: CGFloat = KippleButtonMetrics.historyCategoryButtonSize
        static let rowControlSize: CGFloat = KippleButtonMetrics.historyRowSize
        static let rowCategorySize: CGFloat = KippleButtonMetrics.historyCategoryButtonSize
    }

    enum HistoryFilterIcon {
        static let diameter: CGFloat = HistoryColumns.controlColumnWidth
        static let defaultFont: Font = .system(size: 10, weight: .medium)
        static let pinnedFont: Font = .system(size: 10, weight: .medium)
        static let categoryFont: Font = .system(size: 12, weight: .medium)
        static func font(size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight)
        }
    }

    enum HistoryQueueBadge {
        static let font: Font = .system(size: 11, weight: .semibold)
        static let activeFill = KippleButtonAppearance.inactivePillFill
        static let inactiveFill = Color.clear
        static let activeForeground = TextColor.primary
        static let inactiveForeground = KippleButtonAppearance.inactiveForeground
    }

    enum Notification {
        static let iconFont: Font = .system(size: 11)
        static let textFont: Font = .system(size: 11, weight: .medium)
    }
}
