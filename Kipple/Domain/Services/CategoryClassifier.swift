//
//  CategoryClassifier.swift
//  Kipple
//
//  Centralizes ClipItem category classification and cache handling.
//

import Foundation

// swiftlint:disable cyclomatic_complexity
// swiftlint:disable function_body_length

final class CategoryClassifier {
    static let shared = CategoryClassifier()
    private let cache: CategoryClassifierCache

    init(cache: CategoryClassifierCache = .shared) {
        self.cache = cache
    }

    func classify(content: String, isFromEditor: Bool) -> ClipItemCategory {
        // Editor-origin items are always Kipple
        if isFromEditor { return .kipple }

        // Cache check
        if let cached = cache.get(for: content) {
            return cached
        }

        // Early long-text bailout
        if content.count > 1000 {
            cache.set(.longText, for: content)
            return .longText
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Short text fast path
        if content.count <= 50 {
            if isFilePath(trimmed) { cache.set(.filePath, for: content); return .filePath }
            if isValidEmail(trimmed) { cache.set(.email, for: content); return .email }
            if isValidURL(trimmed) { cache.set(.url, for: content); return .url }
            if isCodeSnippet(trimmed) { cache.set(.code, for: content); return .code }
            cache.set(.shortText, for: content)
            return .shortText
        }

        // 50-1000 chars detailed checks
        if isFilePath(trimmed) { cache.set(.filePath, for: content); return .filePath }
        if isValidEmail(trimmed) { cache.set(.email, for: content); return .email }
        if isValidURL(trimmed) { cache.set(.url, for: content); return .url }
        if isCodeSnippet(trimmed) { cache.set(.code, for: content); return .code }

        if content.count <= 500 { cache.set(.general, for: content); return .general }
        cache.set(.longText, for: content)
        return .longText
    }

    // MARK: - Helpers (ported from ClipItem)

    private func isValidURL(_ text: String) -> Bool {
        if text.hasPrefix("http://") || text.hasPrefix("https://") ||
           text.hasPrefix("ftp://") || text.hasPrefix("file://") {
            return true
        }

        let fileExtensions = [
            ".txt", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
            ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".svg", ".webp",
            ".mp3", ".mp4", ".avi", ".mov", ".mkv", ".wav",
            ".zip", ".rar", ".7z", ".tar", ".gz", ".dmg",
            ".app", ".exe", ".pkg", ".deb", ".rpm",
            ".swift", ".py", ".js", ".java", ".cpp", ".c", ".h",
            ".html", ".css", ".xml", ".json", ".yml", ".yaml"
        ]
        for ext in fileExtensions where text.lowercased().hasSuffix(ext) { return false }

        if !text.contains(" ") && text.count < 200 && !text.contains("/") {
            let components = text.components(separatedBy: ".")
            if components.count >= 2 && components.count <= 4 {
                let lastComponent = components.last ?? ""
                let tldPattern = "^[a-zA-Z]{2,6}$"
                if lastComponent.range(of: tldPattern, options: .regularExpression) != nil {
                    for (index, component) in components.enumerated() where index < components.count - 1 {
                        if component.count < 2 { return false }
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

    private func isValidEmail(_ text: String) -> Bool {
        if text.contains(" ") || text.count > 100 || text.count < 5 { return false }
        if text.contains("..") { return false }

        let emailPattern = "^[A-Z0-9a-z]([A-Z0-9a-z._%+-]*[A-Z0-9a-z])?" +
                          "@[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]\\.[A-Za-z]{2,}$"
        if text.range(of: emailPattern, options: .regularExpression) != nil {
            let parts = text.split(separator: "@")
            if parts.count == 2 {
                let localPart = String(parts[0])
                let domainPart = String(parts[1])
                if localPart.hasPrefix(".") || localPart.hasSuffix(".") { return false }
                if domainPart.hasPrefix(".") || domainPart.hasSuffix(".") ||
                   domainPart.hasPrefix("-") || domainPart.hasSuffix("-") { return false }
                return true
            }
        }
        return false
    }

    private func isFilePath(_ text: String) -> Bool {
        if !isValidPathFormat(text) { return false }
        if text.hasPrefix("/") { return isValidUnixPath(text) }
        if text.hasPrefix("~/") { return text.count > 2 }
        if text.hasPrefix("./") || text.hasPrefix("../") {
            return text.count > (text.hasPrefix("./") ? 2 : 3)
        }
        return isWindowsPath(text)
    }

    private func isValidPathFormat(_ text: String) -> Bool {
        if text.contains(" ") && !text.contains("\\ ") { return false }
        if text.contains("\n") || text.contains("\r") { return false }
        return true
    }

    private func isValidUnixPath(_ text: String) -> Bool {
        if text.count < 3 || text == "/" { return false }
        let components = text.components(separatedBy: "/")
        guard components.count >= 2 else { return false }
        let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        for component in components where !component.isEmpty {
            if component.rangeOfCharacter(from: validChars) == nil { return false }
        }
        return true
    }

    private func isWindowsPath(_ text: String) -> Bool {
        guard text.count > 3 else { return false }
        let firstChar = text.first!
        if (firstChar >= "A" && firstChar <= "Z") || (firstChar >= "a" && firstChar <= "z") {
            let secondIndex = text.index(text.startIndex, offsetBy: 1)
            let thirdIndex = text.index(text.startIndex, offsetBy: 2)
            if text[secondIndex] == ":" && text[thirdIndex] == "\\" { return true }
        }
        return false
    }

    private func isCodeSnippet(_ text: String) -> Bool {
        let checkText = text.count > 500 ? String(text.prefix(500)) : text

        if checkText.hasSuffix(".") || checkText.hasSuffix("。") ||
           checkText.hasSuffix("!") || checkText.hasSuffix("?") {
            let codeSymbols = [
                "{",
                "}",
                "[",
                "]",
                ";",
                "=>",
                "->",
                "==",
                "!=",
                "&&",
                "||",
                "++",
                "--",
                "()",
                "<>",
                "::",
                ":="
            ]
            let symbolCount = codeSymbols.filter { checkText.contains($0) }.count
            if symbolCount < 2 { return false }
        }

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
                    "\\bif\\s+\\w+\\s*:", "\\bfor\\s+\\w+\\s+in\\s+",
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

        for (_, regex) in CodePatterns.patterns {
            if let regex = regex,
               regex.firstMatch(in: checkText, range: NSRange(location: 0, length: checkText.utf16.count)) != nil {
                return true
            }
        }

        let codeSymbols = [
            "{",
            "}",
            "[",
            "]",
            ";",
            "=>",
            "->",
            "==",
            "!=",
            "&&",
            "||",
            "++",
            "--",
            "::",
            ":=",
            "<=",
            ">="
        ]
        let symbolCount = codeSymbols.filter { checkText.contains($0) }.count
        if symbolCount >= 2 { return true }

        if (checkText.hasPrefix("    ") || checkText.hasPrefix("\t")) && checkText.count > 10 {
            return true
        }
        return false
    }
}

// swiftlint:enable function_body_length
// swiftlint:enable cyclomatic_complexity

extension CategoryClassifier: @unchecked Sendable {}
