//
//  CategoryClassifier.swift
//  Kipple
//
//  Simplified classifier that maps clipboard content into URL, Short Text, or Long Text.
//

import Foundation

final class CategoryClassifier {
    static let shared = CategoryClassifier()
    private let cache: CategoryClassifierCache

    init(cache: CategoryClassifierCache = .shared) {
        self.cache = cache
    }

    func classify(content: String, isFromEditor _: Bool) -> ClipItemCategory {
        if let cached = cache.get(for: content) {
            return cached
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if isLikelyURL(trimmed) {
            cache.set(.url, for: content)
            return .url
        }

        cache.set(.all, for: content)
        return .all
    }

    private static let urlDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private static let excludedFileExtensions: [String] = [
        ".txt", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".svg", ".webp",
        ".mp3", ".mp4", ".avi", ".mov", ".mkv", ".wav",
        ".zip", ".rar", ".7z", ".tar", ".gz", ".dmg",
        ".app", ".exe", ".pkg", ".deb", ".rpm",
        ".swift", ".py", ".js", ".java", ".cpp", ".c", ".h",
        ".html", ".css", ".xml", ".json", ".yml", ".yaml", ".md"
    ]

    private func isLikelyURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }

        if trimmed.contains(" ") || trimmed.contains("\n") {
            return false
        }

        let lowercased = trimmed.lowercased()

        // 明示的なスキーム付きの場合のみ URL として許容するスキームを限定
        if trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil,
           let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased() {

            switch scheme {
            case "http", "https", "ftp":
                if let host = url.host, !host.isEmpty { return true }
            case "file":
                if !url.path.isEmpty { return true }
            default:
                return false  // カスタムスキームや mailto は URL カテゴリにしない
            }
        }

        // スキームがない場合はファイル名などの凡ミスを除外
        if Self.excludedFileExtensions.contains(where: { lowercased.hasSuffix($0) }) {
            return false
        }

        // スキームなしだがリンク形状（ドメインのみ等）の場合
        let nsText = trimmed as NSString
        let range = NSRange(location: 0, length: nsText.length)
        if let detector = Self.urlDetector,
           let match = detector.firstMatch(in: trimmed, options: [], range: range),
           match.resultType == .link,
           match.range == range,
           let scheme = match.url?.scheme?.lowercased() {

            // detector が付与したデフォルトスキーム (http/https) だけ URL とみなす
            return ["http", "https"].contains(scheme)
        }

        return false
    }
}

extension CategoryClassifier: @unchecked Sendable {}
