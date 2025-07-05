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
        return String(content.prefix(maxLength)) + "..."
    }
    
    var characterCount: Int {
        content.count
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: timestamp)
    }
    
    var category: ClipItemCategory {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // URL判定
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || 
           (trimmed.contains(".") && !trimmed.contains(" ") && trimmed.count < 100) {
            return .url
        }
        
        // メール判定
        if trimmed.contains("@") && trimmed.contains(".") && !trimmed.contains(" ") && trimmed.count < 100 {
            return .email
        }
        
        // ファイルパス判定
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") || 
           (trimmed.hasPrefix(".") && (trimmed.hasPrefix("./") || trimmed.hasPrefix("../"))) {
            // 拡張子があるか、ディレクトリ区切りがあるかチェック
            if trimmed.contains("/") || trimmed.contains(".") {
                return .filePath
            }
        }
        
        // コード判定（簡易的）
        let codeIndicators = ["{", "}", "(", ")", ";", "=>", "->", "==", "func ", "class ", "struct ", "var ", "let "]
        if codeIndicators.contains(where: { trimmed.contains($0) }) {
            return .code
        }
        
        // 文字数による分類
        if content.count <= 50 {
            return .shortText
        } else if content.count <= 500 {
            return .general
        } else {
            return .longText
        }
    }
    
    init(content: String, isPinned: Bool = false, kind: ClipItemKind = .text, 
         sourceApp: String? = nil, windowTitle: String? = nil, 
         bundleIdentifier: String? = nil, processID: Int32? = nil) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.isPinned = isPinned
        self.kind = kind
        self.sourceApp = sourceApp
        self.windowTitle = windowTitle
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
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
