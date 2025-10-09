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

        if trimmed.contains(" ") || trimmed.contains("\n") || trimmed.contains("@") {
            return false
        }

        let lowercased = trimmed.lowercased()

        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") ||
            lowercased.hasPrefix("ftp://") || lowercased.hasPrefix("file://") {
            if let url = URL(string: trimmed), url.scheme != nil {
                return true
            }
        }

        if Self.excludedFileExtensions.contains(where: { lowercased.hasSuffix($0) }) {
            return false
        }

        let nsText = trimmed as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let detector = Self.urlDetector,
              let match = detector.firstMatch(in: trimmed, options: [], range: range) else {
            return false
        }

        return match.resultType == .link && match.range == range
    }
}

extension CategoryClassifier: @unchecked Sendable {}
