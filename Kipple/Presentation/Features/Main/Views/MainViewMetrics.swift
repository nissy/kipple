//
//  MainViewMetrics.swift
//  Kipple
//
//  Created by Codex on 2025/11/03.
//

import SwiftUI

enum MainViewMetrics {
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
        static let sectionHorizontalPadding: CGFloat = 8
        static let horizontalInset: CGFloat = 2
        static let spacing: CGFloat = 5
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

    enum Notification {
        static let iconFont: Font = .system(size: 11)
        static let textFont: Font = .system(size: 11, weight: .medium)
    }
}
