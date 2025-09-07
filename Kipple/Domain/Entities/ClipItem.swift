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

enum ClipItemCategory: String {
    case url = "URL"
    case email = "Email"
    case code = "Code"
    case filePath = "File"
    case shortText = "Short"
    case longText = "Long"
    case general = "General"
    case kipple = "Kipple"
    
    var icon: String {
        switch self {
        case .url:
            return "link"
        case .email:
            return "envelope"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .filePath:
            return "folder"
        case .shortText:
            return "text.quote"
        case .longText:
            return "doc.text"
        case .general:
            return "doc"
        case .kipple:
            return "square.and.pencil"
        }
    }
}

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let timestamp: Date
    var isPinned: Bool
    let kind: ClipItemKind
    let sourceApp: String?
    let windowTitle: String?
    let bundleIdentifier: String?
    let processID: Int32?
    let isFromEditor: Bool?
    
    // パフォーマンス最適化用の静的フォーマッタ
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
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
        Self.relativeDateFormatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
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
        lhs.id == rhs.id
    }
    
    // 行数を計算
    var lineCount: Int {
        content.components(separatedBy: .newlines).count
    }
    
    // アクション可能かどうか
    var isActionable: Bool {
        switch category {
        case .url, .email, .filePath:
            return true
        default:
            return false
        }
    }
    
    // アクションタイトル
    var actionTitle: String? {
        switch category {
        case .url:
            return "Open in Browser"
        case .email:
            return "Send Email"
        case .filePath:
            return "Show in Finder"
        default:
            return nil
        }
    }
    
    // アクションを実行
    func performAction() {
        switch category {
        case .url:
            if let url = URL(string: content.trimmingCharacters(in: .whitespacesAndNewlines)) {
                NSWorkspace.shared.open(url)
            }
        case .email:
            let emailString = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: "mailto:\(emailString)") {
                NSWorkspace.shared.open(url)
            }
        case .filePath:
            let path = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let expandedPath = NSString(string: path).expandingTildeInPath
            let fileURL = URL(fileURLWithPath: expandedPath)
            
            // ファイルまたはディレクトリが存在するかチェック
            if FileManager.default.fileExists(atPath: expandedPath) {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        default:
            break
        }
    }
}
