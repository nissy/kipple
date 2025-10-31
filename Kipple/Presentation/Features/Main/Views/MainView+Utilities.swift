//
//  MainView+Utilities.swift
//  Kipple
//
//  Created by Kipple on 2025/10/17.
//

import SwiftUI
import AppKit

extension MainView {
    // MARK: - Editor Helpers
    var isEditorEnabled: Bool {
        appSettings.editorPosition != "disabled"
    }

    func confirmAction() {
        viewModel.copyEditor()
        showCopiedNotification(.copied)
    }

    func clearAction() {
        viewModel.clearEditor()
    }

    func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        userPreferredAlwaysOnTop = isAlwaysOnTop
        if isAlwaysOnTopForcedByQueue {
            hasQueueForceOverride = !isAlwaysOnTop
        }
        if isAlwaysOnTopForcedByQueue {
            enforceQueueAlwaysOnTopIfNeeded(
                queueCount: viewModel.pasteQueue.count,
                isQueueModeActive: viewModel.isQueueModeActive
            )
        }
        syncTitleBarState()
        onAlwaysOnTopChanged?(isAlwaysOnTop)
    }

    func toggleEditorVisibility() {
        if appSettings.editorPosition == "disabled" {
            let restore = appSettings.editorPositionLastEnabled
            appSettings.editorPosition = restore.isEmpty ? "bottom" : restore
            editorHeightResetID = UUID()
        } else {
            appSettings.editorPosition = "disabled"
            editorHeightResetID = nil
        }
    }

    func showCopiedNotification(_ type: CopiedNotificationView.NotificationType) {
        currentNotificationType = type
        if !isShowingCopiedNotification {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isShowingCopiedNotification = true
            }
        }

        copiedHideWorkItem?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.isShowingCopiedNotification = false
            }
        }
        copiedHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func formatRemainingTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60

        if minutes > 0 {
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            return String(format: "00:%02d", seconds)
        }
    }

    func clearSystemClipboard() {
        Task {
            await viewModel.clipboardService.clearSystemClipboard()
        }
    }

    func presentCategoryManager() {
        let anchor = NSApp.keyWindow
        CategoryManagerWindowCoordinator.shared.open(
            relativeTo: anchor,
            onOpen: { onSetPreventAutoClose?(true) },
            onClose: { onSetPreventAutoClose?(false) }
        )
    }

    func syncTitleBarState() {
        titleBarState.isAlwaysOnTop = isAlwaysOnTop
        titleBarState.isAlwaysOnTopForcedByQueue = isAlwaysOnTopForcedByQueue
    }
}
