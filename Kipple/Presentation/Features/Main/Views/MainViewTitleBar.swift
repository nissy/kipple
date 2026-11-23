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
    @Published var pasteMode: MainViewModel.PasteMode = .clipboard

    var isQueueActive: Bool { pasteMode != .clipboard }
    
    var toggleAlwaysOnTopHandler: (() -> Void)?
    var toggleEditorHandler: (() -> Void)?
    var startCaptureHandler: (() -> Void)?
    var toggleQueueHandler: (() -> Void)?
    var toggleQueueRepetitionHandler: (() -> Void)?
    var addHistoryItemHandler: (() -> Void)?
    
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

    func requestToggleQueueRepetition() {
        toggleQueueRepetitionHandler?()
    }

    func requestAddHistoryItem() {
        addHistoryItemHandler?()
    }
}

struct MainViewTitleBarAccessory: View {
    @ObservedObject var state: MainWindowTitleBarState
    @ObservedObject private var appSettings = AppSettings.shared
    
    var body: some View {
        titleBarButtons
            .padding(.vertical, 4)
            .background(Color.clear)
    }

    private var titleBarButtons: some View {
        HStack(spacing: MainViewMetrics.toolbarItemSpacing) {
            if state.showsQueueButton {
                queueButton
                if state.isQueueActive { queueRepeatToggle }
            }
            if state.showsCaptureButton {
                captureButton
            }
            
            editorButton
            addHistoryItemButton
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

    var queueRepeatToggle: some View {
        Toggle(isOn: Binding(
            get: { state.pasteMode == .queueToggle },
            set: { isEnabled in
                if isEnabled != (state.pasteMode == .queueToggle) {
                    state.requestToggleQueueRepetition()
                }
            }
        )) {
            Label(appSettings.localizedString("Repeat", comment: "Queue repeat toggle"), systemImage: "repeat")
                .font(MainViewMetrics.TitleBar.iconFont)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .frame(height: MainViewMetrics.TitleBar.buttonSize)
        .background(KippleButtonAppearance.inactivePillFill, in: Capsule())
        .disabled(!state.isQueueEnabled)
        .help(appSettings.localizedString("Queue loop", comment: "Tooltip for queue repeat toggle"))
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

    var addHistoryItemButton: some View {
        let label = appSettings.localizedString("Add History Item")
        return Button(action: state.requestAddHistoryItem) {
            Image(systemName: "plus")
                .font(MainViewMetrics.TitleBar.iconFont)
                .foregroundColor(KippleButtonAppearance.inactiveForeground)
                .frame(width: MainViewMetrics.TitleBar.buttonSize, height: MainViewMetrics.TitleBar.buttonSize)
        }
        .kippleSystemCircleButton()
        .accessibilityLabel(Text(verbatim: label))
        .help(label)
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
                name: .queuePastePermissionRequested,
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
