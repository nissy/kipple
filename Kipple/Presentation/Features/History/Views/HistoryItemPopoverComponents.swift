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

    init(item: ClipItem) {
        self.initialItem = item
        self.itemID = item.id
    }

    private var item: ClipItem {
        adapter.history.first { $0.id == itemID } ?? initialItem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(16)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))

            Text(String(item.content.prefix(500)))
                .font(Font(fontManager.historyFont))
                .lineSpacing(4)
                .lineLimit(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(16)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(NSColor.textBackgroundColor))

            metadataSection
                .padding(16)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 6, y: 3)
    }

    private var headerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: displayCategory.icon)
                    .font(.system(size: 12))
                Text(displayCategory.name)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(displayCategory.color))

            Spacer()

            if item.sourceApp != nil || item.windowTitle != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if let appName = item.sourceApp {
                        HStack(spacing: 4) {
                            Image(systemName: "app.badge.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            Text(appName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }

                    if let windowTitle = item.windowTitle {
                        HStack(spacing: 4) {
                            Image(systemName: "macwindow")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(windowTitle)
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

    private var metadataSection: some View {
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

    private var displayCategory: (name: String, icon: String, color: Color) {
        if let categoryId = item.userCategoryId,
           let category = categoryStore.category(id: categoryId) {
            if let kind = categoryStore.builtInKind(for: category.id) {
                switch kind {
                case .none:
                    return (category.name, categoryStore.iconName(for: category), .gray)
                case .url:
                    return (category.name, categoryStore.iconName(for: category), .blue)
                }
            } else {
                return (category.name, categoryStore.iconName(for: category), Color.accentColor)
            }
        }

        // Fallback to automatic classification
        switch item.category {
        case .url:
            return ("URL", "link", .blue)
        case .all, .shortText, .longText:
            let none = categoryStore.noneCategory()
            return (none.name, categoryStore.iconName(for: none), .gray)
        }
    }
}
