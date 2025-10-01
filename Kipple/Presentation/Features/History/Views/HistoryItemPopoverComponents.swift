//
//  HistoryItemPopoverComponents.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import SwiftUI

struct ClipboardItemPopover: View {
    let item: ClipItem
    @ObservedObject private var fontManager = FontManager.shared

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
                Image(systemName: item.category.icon)
                    .font(.system(size: 12))
                Text(item.category.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(categoryColor))

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

    private var categoryColor: Color {
        switch item.category {
        case .all: return .gray
        case .url, .urls: return .blue
        case .email, .emails: return .green
        case .code: return .purple
        case .filePath, .files: return .orange
        case .shortText: return .orange
        case .longText: return .indigo
        case .numbers: return .cyan
        case .json: return .purple
        case .general: return .gray
        case .kipple: return .accentColor
        }
    }
}
