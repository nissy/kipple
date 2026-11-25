//
//  HistoryItemPopoverComponents.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import SwiftUI
import AppKit

struct ClipboardItemPopover: View {
    private let initialItem: ClipItem
    private let itemID: UUID
    private let screen: NSScreen?
    @ObservedObject private var adapter = ModernClipboardServiceAdapter.shared
    @ObservedObject private var fontManager = FontManager.shared
    @ObservedObject private var categoryStore = UserCategoryStore.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var desktopNotes = DesktopNoteWindowCoordinator.shared

    init(item: ClipItem, screen: NSScreen? = nil) {
        self.initialItem = item
        self.itemID = item.id
        self.screen = screen
    }

    var body: some View {
        let resolvedItem = Self.resolveItem(initialItem: initialItem, itemID: itemID, history: adapter.history)

        return content(for: resolvedItem)
            .environment(\.locale, appSettings.appLocale)
    }

    private func content(for item: ClipItem) -> some View {
        let categories = categoryStore.categories(for: item)
        return HistoryItemPreviewContent(
            item: item,
            categories: categories.isEmpty ? [categoryStore.noneCategory()] : categories,
            historyFont: fontManager.historyFont,
            isPosted: desktopNotes.isPosted(item.id)
        ) {
            desktopNotes.toggle(item, on: screen)
        }
    }
}

extension ClipboardItemPopover {
    static func resolveItem(initialItem: ClipItem, itemID: UUID, history: [ClipItem]) -> ClipItem {
        history.first { $0.id == itemID } ?? initialItem
    }

    static func makePreviewText(for item: ClipItem, maxLength: Int = 500) -> String {
        HistoryItemPreviewContent.makePreviewText(for: item, maxLength: maxLength)
    }
}
