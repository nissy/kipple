//
//  GlassDesignConstants.swift
//  Kipple
//
//  Shared constants for glass surfaces.
//

import SwiftUI
import AppKit

enum KippleGlassMetrics {
    static let windowCornerRadius: CGFloat = 24
    static let panelCornerRadius: CGFloat = 14
    static let inputCornerRadius: CGFloat = 9
    static let compactInputCornerRadius: CGFloat = 8
    static let controlStrokeWidth: CGFloat = 0.6
    static let adjacentWindowSpacing: CGFloat = 16

    static let mainWindowDefaultSize = NSSize(width: 420, height: 600)
    static let mainWindowMinimumSize = NSSize(width: 375, height: 520)
    static let mainWindowMaximumSize = NSSize(width: 800, height: 1200)
    static let mainWindowOversizedMigrationThreshold = NSSize(width: 700, height: 900)
    static let settingsWindowSize = NSSize(width: 460, height: 380)
}

enum KippleGlassAppearance {
    static let controlFill = Color(NSColor.textBackgroundColor).opacity(0.42)
    static let controlStroke = Color.primary.opacity(0.06)
    static let subtlePanelFill = Color.primary.opacity(0.025)
    static let toolbarFill = Color.white.opacity(0.06)
    static let toolbarStroke = Color.white.opacity(0.1)

    static func toolbarItemFill(isSelected: Bool) -> Color {
        Color.white.opacity(isSelected ? 0.08 : 0.06)
    }

    static func toolbarItemStroke(isSelected: Bool) -> Color {
        Color.white.opacity(isSelected ? 0.18 : 0.1)
    }
}
