//
//  MainViewMetrics.swift
//  Kipple
//
//  Created by Codex on 2025/11/03.
//

import SwiftUI

enum MainViewMetrics {
    static let contentHorizontalInset: CGFloat = 16
    static let toolbarItemSpacing: CGFloat = 8

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
        static let height = HistoryRows.height
    }

    enum HistoryFilterSidebar {
        static let width = HistoryColumns.rowControlSize
        static let contentSpacing: CGFloat = 11
        static let iconFont = TitleBar.iconFont
    }

    enum HistoryRows {
        static let height: CGFloat = 32
        static let spacing: CGFloat = 2
        static let verticalPadding: CGFloat = 4
    }

    enum HistoryColumns {
        static let spacing: CGFloat = 5
        static let toolbarBottomPadding: CGFloat = 6
        static let rowLeadingInset: CGFloat = 8
        static let controlColumnWidth: CGFloat = KippleButtonMetrics.historyCategoryButtonSize
        static let trailingControlInset = (TitleBar.buttonSize - controlColumnWidth) / 2
        static let rowControlSize: CGFloat = KippleButtonMetrics.historyRowSize
        static let rowCategorySize: CGFloat = KippleButtonMetrics.historyCategoryButtonSize
    }

    enum HistoryFilterIcon {
        static let diameter: CGFloat = HistoryColumns.controlColumnWidth
        static let defaultFont: Font = .system(size: 10, weight: .medium)
    }

    enum HistoryQueueBadge {
        static let font: Font = .system(size: 11, weight: .semibold)
        static let activeFill = AnyShapeStyle(KippleButtonAppearance.circleFill(isActive: true))
        static let inactiveFill = AnyShapeStyle(Color.clear)
        static let activeForeground = KippleButtonAppearance.activeForeground
        static let inactiveForeground = KippleButtonAppearance.inactiveForeground
    }

    enum Notification {
        static let iconFont: Font = .system(size: 11)
        static let textFont: Font = .system(size: 11, weight: .medium)
    }
}
