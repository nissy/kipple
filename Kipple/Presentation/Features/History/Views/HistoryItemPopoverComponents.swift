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
            if let title = item.title {
                Text(verbatim: title).font(.headline).padding([.top, .horizontal], 16)
            }
            if item.metadata?.sources.contains(.mcp) == true {
                Text("Added via MCP").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            }
            if item.metadata?.sources.contains(.ocr) == true {
                Text("Captured with OCR").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            }
            headerSection(for: item)
                .padding(16)

            Divider()
                .opacity(0.08)

            Text(verbatim: previewText)
                .font(Font(fontManager.historyFont))
                .foregroundColor(MainViewMetrics.TextColor.primary)
                .lineSpacing(4)
                .lineLimit(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(16)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .opacity(0.07)

            metadataSection(for: item)
                .padding(16)
        }
        .frame(width: 320)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func headerSection(for item: ClipItem) -> some View {
        let categories = categoryStore.categories(for: item)

        return VStack(alignment: .leading, spacing: 10) {
            CategoryLabelsView(categories: categories.isEmpty ? [categoryStore.noneCategory()] : categories, isPreview: true)

            if item.sourceApp != nil || item.windowTitle != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if let appName = item.sourceApp {
                        HStack(spacing: 4) {
                            Image(systemName: "app.badge.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            Text(localizedAppName(appName))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(MainViewMetrics.TextColor.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(appName)
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
                .frame(maxWidth: .infinity, alignment: .trailing)
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
                    .foregroundColor(MainViewMetrics.TextColor.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Copied")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(item.formattedTimestamp)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(MainViewMetrics.TextColor.primary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private func localizedAppName(_ appName: String) -> String {
        if appName == "External Source" {
            return String(localized: "External Source")
        }
        return appName
    }

    private func localizedWindowTitle(_ title: String) -> String {
        if title == "Quick Editor" || title == "Live Editor" {
            return String(localized: "Live Editor")
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
