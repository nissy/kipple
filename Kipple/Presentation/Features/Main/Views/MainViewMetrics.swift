//
//  MainViewMetrics.swift
//  Kipple
//
//  Created by Codex on 2025/11/03.
//

import SwiftUI

enum MainViewMetrics {
    enum TitleBar {
        static let buttonSize: CGFloat = 30
        static let iconFont: Font = .system(size: 12, weight: .medium)
        static let badgeFont: Font = .system(size: 11, weight: .bold)
        static let badgeOffset = CGSize(width: -2, height: 2)
    }
    
    enum BottomBar {
        static let buttonSize: CGFloat = 30
        static let iconFont: Font = .system(size: 12, weight: .medium)
        static let clipboardIconFont: Font = .system(size: 11)
        static let clearIconFont: Font = .system(size: 12)
        static let autoClearIconFont: Font = .system(size: 11)
        static let autoClearTimerFont: Font = .system(size: 11, design: .monospaced)
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

    enum HistoryFilterIcon {
        static let diameter: CGFloat = 22
        static let defaultFont: Font = .system(size: 12, weight: .medium)
        static let pinnedFont: Font = .system(size: 10, weight: .medium)
        static let categoryFont: Font = .system(size: 13, weight: .medium)
        static func font(size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight)
        }
    }

    enum Notification {
        static let iconFont: Font = .system(size: 11)
        static let textFont: Font = .system(size: 11, weight: .medium)
    }
}
