//
//  SettingsLayoutMetrics.swift
//  Kipple
//
//  Created by Kipple on 2025/10/10.
//

import SwiftUI

enum SettingsLayoutMetrics {
    static let windowMinWidth: CGFloat = KippleGlassMetrics.settingsWindowSize.width
    static let windowIdealWidth: CGFloat = KippleGlassMetrics.settingsWindowSize.width + 20
    static let windowMaxWidth: CGFloat = KippleGlassMetrics.settingsWindowSize.width + 100
    static let windowMinHeight: CGFloat = KippleGlassMetrics.settingsWindowSize.height
    static let scrollHorizontalPadding: CGFloat = 12
    static let scrollVerticalPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 14
    static let groupContainerSpacing: CGFloat = 4
    static let groupDividerBottomPadding: CGFloat = 3
    static let groupHeaderSpacing: CGFloat = 5
    static let groupContentSpacing: CGFloat = 6
    static let groupContentIndent: CGFloat = 10
    static let groupTopPaddingWithDivider: CGFloat = 6
    static let groupTopPaddingWithoutDivider: CGFloat = 3
    static let groupBottomPadding: CGFloat = 6
    static let toolbarSpacing: CGFloat = 8
    static let toolbarHorizontalPadding: CGFloat = 12
    static let toolbarTopPadding: CGFloat = 8
    static let toolbarBottomPadding: CGFloat = 6
    static let toolbarButtonWidth: CGFloat = 96
    static let toolbarButtonHorizontalPadding: CGFloat = 5
    static let toolbarButtonVerticalPadding: CGFloat = 2
    static let toolbarIconSize: CGFloat = 32
    static let toolbarIconFontSize: CGFloat = 15
    static let toolbarLabelFontSize: CGFloat = 11
    static let toolbarLabelScaleFactor: CGFloat = 0.85
    static let rowLabelWidth: CGFloat = 150
    static let rowHorizontalSpacing: CGFloat = 10
    static let rowVerticalSpacing: CGFloat = 2
    static let rowVerticalPadding: CGFloat = 1
    static let inlineDescriptionLeadingPadding: CGFloat = 3
}
