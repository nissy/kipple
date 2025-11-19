//
//  HistoryItemPopoverComponents.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import SwiftUI

struct ClipboardItemPopover: View {
    private let initialItem: ClipItem
    private let itemID: UUID
    @ObservedObject private var adapter = ModernClipboardServiceAdapter.shared
    @ObservedObject private var fontManager = FontManager.shared
    @ObservedObject private var categoryStore = UserCategoryStore.shared
    @ObservedObject private var appSettings = AppSettings.shared

    init(item: ClipItem) {
        self.initialItem = item
        self.itemID = item.id
    }

    var body: some View {
        let resolvedItem = Self.resolveItem(initialItem: initialItem, itemID: itemID, history: adapter.history)

        return content(for: resolvedItem)
            .environment(\.locale, appSettings.appLocale)
    }

    private func content(for item: ClipItem) -> some View {
        let previewText = Self.makePreviewText(for: item)
        return VStack(alignment: .leading, spacing: 0) {
            headerSection(for: item)
                .padding(16)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))

            Text(verbatim: previewText)
                .font(Font(fontManager.historyFont))
                .lineSpacing(4)
                .lineLimit(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(16)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(NSColor.textBackgroundColor))

            metadataSection(for: item)
                .padding(16)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 6, y: 3)
    }

    private func headerSection(for item: ClipItem) -> some View {
        let categoryInfo = displayCategory(for: item)

        return HStack {
            HStack(spacing: 6) {
                Image(systemName: categoryInfo.icon)
                    .font(.system(size: 12))
                Text(verbatim: categoryInfo.name)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(categoryInfo.color))

            Spacer()

            if item.sourceApp != nil || item.windowTitle != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if let appName = item.sourceApp {
                        HStack(spacing: 4) {
                            Image(systemName: "app.badge.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            Text(localizedAppName(appName))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }

                    if let windowTitle = item.windowTitle {
                        HStack(spacing: 4) {
                            Image(systemName: "macwindow")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(localizedWindowTitle(windowTitle))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
        }
    }

    private func metadataSection(for item: ClipItem) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Characters")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("\(item.characterCount)")
                    .font(.system(size: 10, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Copied")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(item.formattedTimestamp)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private struct DisplayCategoryInfo {
        let name: String
        let icon: String
        let color: Color
    }

    private func displayCategory(for item: ClipItem) -> DisplayCategoryInfo {
        if let categoryId = item.userCategoryId,
           let category = categoryStore.category(id: categoryId) {
            if let kind = categoryStore.builtInKind(for: category.id) {
                switch kind {
                case .none:
                    return DisplayCategoryInfo(
                        name: category.name,
                        icon: categoryStore.iconName(for: category),
                        color: .gray
                    )
                case .url:
                    return DisplayCategoryInfo(
                        name: category.name,
                        icon: categoryStore.iconName(for: category),
                        color: .blue
                    )
                }
            } else {
                return DisplayCategoryInfo(
                    name: category.name,
                    icon: categoryStore.iconName(for: category),
                    color: Color.accentColor
                )
            }
        }

        // Fallback to automatic classification
        switch item.category {
        case .url:
            return DisplayCategoryInfo(
                name: String(localized: "URL"),
                icon: "link",
                color: .blue
            )
        case .all:
            let none = categoryStore.noneCategory()
            return DisplayCategoryInfo(
                name: none.name,
                icon: categoryStore.iconName(for: none),
                color: .gray
            )
        }
    }

    private func localizedAppName(_ appName: String) -> String {
        if appName == "External Source" {
            return String(localized: "External Source")
        }
        return appName
    }

    private func localizedWindowTitle(_ title: String) -> String {
        if title == "Quick Editor" {
            return String(localized: "Quick Editor")
        }
        return title
    }
}

extension ClipboardItemPopover {
    static func resolveItem(initialItem: ClipItem, itemID: UUID, history: [ClipItem]) -> ClipItem {
        history.first { $0.id == itemID } ?? initialItem
    }

    static func makePreviewText(for item: ClipItem, maxLength: Int = 500) -> String {
        String(item.content.prefix(maxLength))
    }
}
