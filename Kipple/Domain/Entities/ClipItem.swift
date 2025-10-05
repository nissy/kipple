//
//  ClipItem.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Foundation
import AppKit

enum ClipItemKind: String, Codable {
    case text
    case image
    case file
    case url
}

enum ClipItemCategory: String, CaseIterable {
    case all = "All"
    case url = "URL"
    case shortText = "Short Text"
    case longText = "Long Text"

    var icon: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .url:
            return "link"
        case .shortText:
            return "text.quote"
        case .longText:
            return "doc.text"
        }
    }
}

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    var timestamp: Date
    var isPinned: Bool
    let kind: ClipItemKind
    let sourceApp: String?
    let windowTitle: String?
    let bundleIdentifier: String?
    let processID: Int32?
    let isFromEditor: Bool?
    
    // パフォーマンス最適化用の静的フォーマッタ
    private static func makeRelativeDateFormatter() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }
    
    private static func makeTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
    
    // Computed properties
    var fullContent: String {
        content
    }
    
    var displayContent: String {
        let maxLength = 50
        guard content.count > maxLength else {
            return content
        }
        // prefix は効率的なので問題ないが、早期リターンで無駄な処理を削減
        return String(content.prefix(maxLength)) + "…"
    }
    
    var characterCount: Int {
        content.count
    }
    
    var timeAgo: String {
        Self.makeRelativeDateFormatter().localizedString(for: timestamp, relativeTo: Date())
    }
    
    var formattedTimestamp: String {
        Self.makeTimestampFormatter().string(from: timestamp)
    }
    
    var category: ClipItemCategory {
        CategoryClassifier.shared.classify(content: content, isFromEditor: isFromEditor ?? false)
    }
    
    init(
        content: String,
        isPinned: Bool = false,
        kind: ClipItemKind = .text,
        sourceApp: String? = nil,
        windowTitle: String? = nil,
        bundleIdentifier: String? = nil,
        processID: Int32? = nil,
        isFromEditor: Bool = false
    ) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.isPinned = isPinned
        self.kind = kind
        self.sourceApp = sourceApp
        self.windowTitle = windowTitle
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.isFromEditor = isFromEditor
    }
    
    init(
        id: UUID,
        content: String,
        timestamp: Date,
        isPinned: Bool,
        kind: ClipItemKind,
        sourceApp: String?,
        windowTitle: String?,
        bundleIdentifier: String?,
        processID: Int32?,
        isFromEditor: Bool?
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.kind = kind
        self.sourceApp = sourceApp
        self.windowTitle = windowTitle
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.isFromEditor = isFromEditor
    }
    
    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.content == rhs.content &&
        lhs.isPinned == rhs.isPinned &&
        lhs.timestamp == rhs.timestamp &&
        lhs.kind == rhs.kind &&
        lhs.sourceApp == rhs.sourceApp &&
        lhs.windowTitle == rhs.windowTitle &&
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.processID == rhs.processID &&
        lhs.isFromEditor == rhs.isFromEditor
    }
    
    // 行数を計算
    var lineCount: Int {
        content.components(separatedBy: .newlines).count
    }
    
    // アクション可能かどうか（テキストかつURIスキーム判定のみ）
    var isActionable: Bool {
        return kind == .text && resolveURISchemeURL() != nil
    }
    
    // アクションタイトル
    var actionTitle: String? {
        if let scheme = resolveURISchemeURL()?.scheme?.uppercased() {
            return "Open \(scheme)"
        }
        return nil
    }
    
    // アクションを実行（URIスキームのみ）
    func performAction() {
        guard let uri = resolveURISchemeURL() else { return }
        NSWorkspace.shared.open(uri)
    }

    // 最初に解釈可能なURIスキームURLを返す（mailto自動付与はしない）
    private func resolveURISchemeURL() -> URL? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // 先頭にスキームがある場合
        if trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil,
           let url = URL(string: trimmed) {
            return url
        }
        return nil
    }
}
