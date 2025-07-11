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
        return String(content.prefix(maxLength)) + "..."
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
        // エディタからコピーされたアイテムは常にKippleカテゴリ
        if isFromEditor == true {
            return .kipple
        }
        
        // パフォーマンス最適化: 大量テキストは早期にlongTextとして分類
        if content.count > 1000 {
            return .longText
        }
        
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 判定優先順位：文字数チェック > ファイルパス > メール > URL > コード
        
        // 短いテキストの早期分類
        if content.count <= 50 {
            // 短いテキストでも特殊なパターンをチェック
            if isFilePath(trimmed) {
                return .filePath
            }
            if isValidEmail(trimmed) {
                return .email
            }
            if isValidURL(trimmed) {
                return .url
            }
            // 短いテキストでもコードの可能性をチェック
            if isCodeSnippet(trimmed) {
                return .code
            }
            return .shortText
        }
        
        // 中程度のテキスト（50-1000文字）のみ詳細な判定
        
        // ファイルパス判定（最優先）
        if isFilePath(trimmed) {
            return .filePath
        }
        
        // メール判定
        if isValidEmail(trimmed) {
            return .email
        }
        
        // URL判定
        if isValidURL(trimmed) {
            return .url
        }
        
        // コード判定（重い処理なので最後に）
        if isCodeSnippet(trimmed) {
            return .code
        }
        
        // 文字数による分類
        if content.count <= 500 {
            return .general
        } else {
            return .longText
        }
    }
    
    // URL判定を改善
    private func isValidURL(_ text: String) -> Bool {
        // 明確なURLプロトコル
        if text.hasPrefix("http://") || text.hasPrefix("https://") || 
           text.hasPrefix("ftp://") || text.hasPrefix("file://") {
            return true
        }
        
        // 一般的なファイル拡張子を除外
        let fileExtensions = [
            ".txt", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
            ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".svg", ".webp",
            ".mp3", ".mp4", ".avi", ".mov", ".mkv", ".wav",
            ".zip", ".rar", ".7z", ".tar", ".gz", ".dmg",
            ".app", ".exe", ".pkg", ".deb", ".rpm",
            ".swift", ".py", ".js", ".java", ".cpp", ".c", ".h",
            ".html", ".css", ".xml", ".json", ".yml", ".yaml"
        ]
        
        for ext in fileExtensions where text.lowercased().hasSuffix(ext) {
            return false
        }
        
        // より厳密なドメイン形式のチェック
        if !text.contains(" ") && text.count < 200 && !text.contains("/") {
            let components = text.components(separatedBy: ".")
            if components.count >= 2 && components.count <= 4 {
                // 最後の要素がTLD（2-6文字の英字）であることを確認
                let lastComponent = components.last ?? ""
                let tldPattern = "^[a-zA-Z]{2,6}$"
                if lastComponent.range(of: tldPattern, options: .regularExpression) != nil {
                    // 各要素が妥当なドメイン名であることを確認
                    for (index, component) in components.enumerated() where index < components.count - 1 {
                        // 最後のTLD以外をチェック
                        // ドメイン名は2文字以上、英数字とハイフンのみ
                        if component.count < 2 {
                            return false
                        }
                        let domainPattern = "^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]+$"
                        if component.range(of: domainPattern, options: .regularExpression) == nil {
                            return false
                        }
                    }
                    return true
                }
            }
        }
        
        return false
    }
    
    // メール判定を改善
    private func isValidEmail(_ text: String) -> Bool {
        if text.contains(" ") || text.count > 100 || text.count < 5 {
            return false
        }
        
        // 連続するピリオドを除外
        if text.contains("..") {
            return false
        }
        
        // より厳密なメールパターン（RFC準拠に近い）
        // ローカル部は1文字以上、または._%+-を含む複数文字を許可
        let emailPattern = "^[A-Z0-9a-z]([A-Z0-9a-z._%+-]*[A-Z0-9a-z])?" +
                          "@[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]\\.[A-Za-z]{2,}$"
        if text.range(of: emailPattern, options: .regularExpression) != nil {
            // @の前後をチェック
            let parts = text.split(separator: "@")
            if parts.count == 2 {
                let localPart = String(parts[0])
                let domainPart = String(parts[1])
                
                // ローカル部の検証
                if localPart.hasPrefix(".") || localPart.hasSuffix(".") {
                    return false
                }
                
                // ドメイン部の検証
                if domainPart.hasPrefix(".") || domainPart.hasSuffix(".") ||
                   domainPart.hasPrefix("-") || domainPart.hasSuffix("-") {
                    return false
                }
                
                return true
            }
        }
        
        return false
    }
    
    // ファイルパス判定を改善
    private func isFilePath(_ text: String) -> Bool {
        // スペースを含む場合は基本的にファイルパスではない（ただし、エスケープされている場合を除く）
        if text.contains(" ") && !text.contains("\\ ") {
            return false
        }
        
        // 改行を含む場合はファイルパスではない
        if text.contains("\n") || text.contains("\r") {
            return false
        }
        
        // Unix/Mac絶対パス
        if text.hasPrefix("/") {
            // ただし、単なるスラッシュや短すぎるパスは除外
            if text.count < 3 || text == "/" {
                return false
            }
            // パス区切り文字を含むかチェック
            let components = text.components(separatedBy: "/")
            // 少なくとも2つ以上のコンポーネントが必要
            if components.count >= 2 {
                // 各コンポーネントが妥当かチェック（空文字や特殊文字のみは除外）
                for component in components {
                    if component.isEmpty { continue }
                    // ファイル名として妥当な文字を含むかチェック
                    let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
                    if component.rangeOfCharacter(from: validChars) == nil {
                        return false
                    }
                }
                return true
            }
        }
        
        // ホームディレクトリ
        if text.hasPrefix("~/") {
            // ~/の後に何か続く必要がある
            return text.count > 2
        }
        
        // 相対パス
        if text.hasPrefix("./") || text.hasPrefix("../") {
            // ./や../の後に何か続く必要がある
            return text.count > (text.hasPrefix("./") ? 2 : 3)
        }
        
        // Windowsパス（より厳密なチェック）
        if text.count > 3 {
            // ドライブレターのチェック（A-Z, a-z）
            let firstChar = text.first!
            if (firstChar >= "A" && firstChar <= "Z") || (firstChar >= "a" && firstChar <= "z") {
                let secondIndex = text.index(text.startIndex, offsetBy: 1)
                let thirdIndex = text.index(text.startIndex, offsetBy: 2)
                if text[secondIndex] == ":" && text[thirdIndex] == "\\" {
                    return true
                }
            }
        }
        
        return false
    }
    
    // コード判定を改善
    private func isCodeSnippet(_ text: String) -> Bool {
        // パフォーマンス最適化: 大量テキストは最初の一部のみをチェック
        let checkText = text.count > 500 ? String(text.prefix(500)) : text
        
        // 自然言語の文章を除外（文末がピリオドで終わる場合）
        if checkText.hasSuffix(".") || checkText.hasSuffix("。") ||
           checkText.hasSuffix("!") || checkText.hasSuffix("?") {
            // ただし、コードの可能性がある場合は続行
            let codeSymbols = [
                "{", "}", "[", "]", ";", "=>", "->", "==", "!=", 
                "&&", "||", "++", "--", "()", "<>", "::", ":="
            ]
            let symbolCount = codeSymbols.filter { checkText.contains($0) }.count
            if symbolCount < 2 {
                return false
            }
        }
        
        // 静的な正規表現パターン（コンパイル済み）
        struct CodePatterns {
            static let patterns: [(String, NSRegularExpression?)] = {
                let patternStrings = [
                    // 関数・メソッド定義
                    "\\bfunc\\s+\\w+", "\\bfunction\\s+\\w+", "\\bdef\\s+\\w+",
                    // クラス・構造体定義
                    "\\bclass\\s+\\w+", "\\bstruct\\s+\\w+", "\\binterface\\s+\\w+",
                    // 変数定義
                    "\\bvar\\s+\\w+", "\\blet\\s+\\w+", "\\bconst\\s+\\w+",
                    // 制御構造
                    "\\bif\\s*\\(", "\\bfor\\s*\\(", "\\bwhile\\s*\\(",
                    "\\bif\\s+\\w+\\s*:", "\\bfor\\s+\\w+\\s+in\\s+", // Python風
                    // その他の言語構造
                    "\\bimport\\s+\\w+", "#include\\s*[<\"]", "\\busing\\s+namespace",
                    "\\breturn\\s+", "\\bthrow\\s+", "\\btry\\s*\\{", "\\bcatch\\s*\\(",
                    // 型定義
                    "\\bpublic\\s+class", "\\bprivate\\s+", "\\bprotected\\s+",
                    // コメント
                    "^\\s*//", "^\\s*/\\*", "^\\s*#",
                    // SQL
                    "\\bSELECT\\s+.*\\sFROM\\b", "\\bINSERT\\s+INTO\\b",
                    "\\bUPDATE\\s+.*\\sSET\\b", "\\bDELETE\\s+FROM\\b",
                    // アロー関数とメソッドチェーン
                    "=>", "\\.\\w+\\(.*\\)"
                ]
                return patternStrings.map { pattern in
                    (pattern, try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))
                }
            }()
        }
        
        // コンパイル済み正規表現を使用
        for (_, regex) in CodePatterns.patterns {
            if let regex = regex,
               regex.firstMatch(in: checkText,
                                options: [],
                                range: NSRange(checkText.startIndex..., in: checkText)) != nil {
                return true
            }
        }
        
        // 複数のコード記号を含む場合
        let codeSymbols = [
            "{", "}", "[", "]", ";", "=>", "->", "==", "!=",
            "&&", "||", "++", "--", "::", ":=", "<=", ">="
        ]
        let symbolCount = codeSymbols.filter { checkText.contains($0) }.count
        if symbolCount >= 2 {
            return true
        }
        
        // インデントされたコード（4スペースまたはタブで始まる）
        // ただし、非常に短いテキストは除外
        if (checkText.hasPrefix("    ") || checkText.hasPrefix("\t")) && checkText.count > 10 {
            return true
        }
        
        return false
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
