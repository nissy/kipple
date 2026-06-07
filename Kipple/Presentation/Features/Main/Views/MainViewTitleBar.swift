//
//  MainViewTitleBar.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI
import Combine

final class MainWindowTitleBarState: ObservableObject {
    @Published var isAlwaysOnTop: Bool = false
    @Published var isAlwaysOnTopForcedByQueue: Bool = false
    @Published var isEditorEnabled: Bool = true
    @Published var showsCaptureButton: Bool = false
    @Published var isCaptureEnabled: Bool = false
    @Published var showsQueueButton: Bool = false
    @Published var isQueueEnabled: Bool = false
    @Published var isQueueActive: Bool = false
    
    var toggleAlwaysOnTopHandler: (() -> Void)?
    var toggleEditorHandler: (() -> Void)?
    var startCaptureHandler: (() -> Void)?
    var toggleQueueHandler: (() -> Void)?
    
    func requestToggleAlwaysOnTop() {
        toggleAlwaysOnTopHandler?()
    }
    
    func requestToggleEditor() {
        toggleEditorHandler?()
    }
    
    func requestStartCapture() {
        startCaptureHandler?()
    }
    
    func requestToggleQueue() {
        toggleQueueHandler?()
    }
}

struct MainViewTitleBarAccessory: View {
    @ObservedObject var state: MainWindowTitleBarState
    @ObservedObject private var appSettings = AppSettings.shared
    
    var body: some View {
        titleBarButtons
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.clear)
    }

    private var titleBarButtons: some View {
        HStack(spacing: 8) {
            if state.showsQueueButton {
                queueButton
            }
            if state.showsCaptureButton {
                captureButton
            }
            
            editorButton
        }
    }
}

private extension MainViewTitleBarAccessory {
    var captureHelpText: String {
        appSettings.localizedString("Screen Text Capture", comment: "Tooltip for screen text capture button")
    }

    var queueHelpText: String {
        appSettings.localizedString("Queue paste mode", comment: "Tooltip for queue toggle button")
    }

    var hideEditorHelpText: String {
        appSettings.localizedString("Hide editor panel", comment: "Tooltip when editor is visible")
    }

    var showEditorHelpText: String {
        appSettings.localizedString("Show editor panel", comment: "Tooltip when editor is hidden")
    }

    var captureButton: some View {
        let content = ZStack {
            Image(systemName: "text.magnifyingglass")
                .font(MainViewMetrics.TitleBar.iconFont)
                .foregroundColor(KippleButtonAppearance.inactiveForeground)
        }
        .frame(
            width: MainViewMetrics.TitleBar.buttonSize,
            height: MainViewMetrics.TitleBar.buttonSize
        )
        
        return Button(action: handleCaptureButtonTap) {
            content
        }
        .kippleSystemCircleButton()
        .help(captureHelpText)
        .overlay(permissionBadge(isActive: state.isCaptureEnabled), alignment: .topTrailing)
        .focusable(false)
        .focusEffectDisabled()
    }
    
    var queueButton: some View {
        let content = ZStack {
            Image(systemName: "list.number")
                .font(MainViewMetrics.TitleBar.iconFont)
                .foregroundColor(queueIconColor)
        }
        .frame(
            width: MainViewMetrics.TitleBar.buttonSize,
            height: MainViewMetrics.TitleBar.buttonSize
        )
        
        return Button(action: handleQueueButtonTap) {
            content
        }
        .kippleSystemCircleButton(isActive: state.isQueueActive)
        .help(queueHelpText)
        .overlay(permissionBadge(isActive: state.isQueueEnabled), alignment: .topTrailing)
        .focusable(false)
        .focusEffectDisabled()
    }
    
    var editorButton: some View {
        Button(action: state.requestToggleEditor) {
            ZStack {
                Image(systemName: state.isEditorEnabled ? "square.and.pencil" : "square.slash")
                    .font(MainViewMetrics.TitleBar.iconFont)
                    .foregroundColor(KippleButtonAppearance.foreground(isActive: state.isEditorEnabled))
            }
            .frame(
                width: MainViewMetrics.TitleBar.buttonSize,
                height: MainViewMetrics.TitleBar.buttonSize
            )
        }
        .kippleSystemCircleButton(isActive: state.isEditorEnabled)
        .help(state.isEditorEnabled ? hideEditorHelpText : showEditorHelpText)
        .focusable(false)
        .focusEffectDisabled()
    }
    
    private var queueIconColor: Color {
        KippleButtonAppearance.foreground(isActive: state.isQueueActive)
    }
    
    private func handleCaptureButtonTap() {
        if state.isCaptureEnabled {
            state.requestStartCapture()
        } else {
            NotificationCenter.default.post(
                name: .screenRecordingPermissionRequested,
                object: nil
            )
        }
    }
    
    private func handleQueueButtonTap() {
        if state.isQueueEnabled {
            state.requestToggleQueue()
        } else {
            NotificationCenter.default.post(
                name: .accessibilityPermissionRequested,
                object: nil
            )
        }
    }
    
    private func permissionBadge(isActive: Bool) -> some View {
        Group {
            if !isActive {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(MainViewMetrics.TitleBar.badgeFont)
                    .foregroundColor(KippleButtonAppearance.permissionWarningForeground)
                    .shadow(color: KippleButtonAppearance.permissionWarningShadow, radius: 1, y: 1)
                    .offset(
                        x: MainViewMetrics.TitleBar.badgeOffset.width,
                        y: MainViewMetrics.TitleBar.badgeOffset.height
                    )
            }
        }
    }
}

struct MainViewTitleBarPinButton: View {
    @ObservedObject var state: MainWindowTitleBarState
    @ObservedObject private var appSettings = AppSettings.shared
    
    var body: some View {
        Button(action: state.requestToggleAlwaysOnTop) {
            ZStack {
                Image(systemName: state.isAlwaysOnTop ? "pin.fill" : "pin")
                    .font(MainViewMetrics.TitleBar.iconFont)
                    .foregroundColor(KippleButtonAppearance.foreground(isActive: state.isAlwaysOnTop))
                    .rotationEffect(.degrees(state.isAlwaysOnTop ? 0 : -45))
                    .frame(
                        width: MainViewMetrics.TitleBar.buttonSize,
                        height: MainViewMetrics.TitleBar.buttonSize
                    )
            }
        }
        .kippleSystemCircleButton(isActive: state.isAlwaysOnTop)
        .help(
            state.isAlwaysOnTopForcedByQueue && !state.isAlwaysOnTop
                ? queueForcedHelpText
                : (state.isAlwaysOnTop ? disableAlwaysOnTopHelpText : enableAlwaysOnTopHelpText)
        )
        .focusable(false)
        .focusEffectDisabled()
    }
}

private extension MainViewTitleBarPinButton {
    var queueForcedHelpText: String {
        appSettings.localizedString(
            "Queue mode is active but Always on Top is disabled",
            comment: "Tooltip when queue forces always on top but is disabled"
        )
    }

    var disableAlwaysOnTopHelpText: String {
        appSettings.localizedString("Disable always on top", comment: "Tooltip when disabling always on top")
    }

    var enableAlwaysOnTopHelpText: String {
        appSettings.localizedString("Enable always on top", comment: "Tooltip when enabling always on top")
    }
}
