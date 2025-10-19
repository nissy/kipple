//
//  MainView+Utilities.swift
//  Kipple
//
//  Created by Kipple on 2025/10/17.
//

import SwiftUI
import AppKit

extension MainView {
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
}
