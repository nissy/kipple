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
    private let shortTextThreshold = 200

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

    private func isLikelyURL(_ text: String) -> Bool {
        guard text.count >= 4 else { return false }

        if text.contains(" ") || text.contains("\n") || text.contains("@") {
            return false
        }

        let lowercased = text.lowercased()

        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") ||
            lowercased.hasPrefix("ftp://") || lowercased.hasPrefix("file://") {
            return true
        }

        let fileExtensions = [
            ".txt", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
            ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".svg", ".webp",
            ".mp3", ".mp4", ".avi", ".mov", ".mkv", ".wav",
            ".zip", ".rar", ".7z", ".tar", ".gz", ".dmg",
            ".app", ".exe", ".pkg", ".deb", ".rpm",
            ".swift", ".py", ".js", ".java", ".cpp", ".c", ".h",
            ".html", ".css", ".xml", ".json", ".yml", ".yaml", ".md"
        ]
        if fileExtensions.contains(where: { lowercased.hasSuffix($0) }) {
            return false
        }

        let components = lowercased.split(separator: ".")
        guard components.count >= 2, components.count <= 4 else { return false }
        guard let tld = components.last, (2...10).contains(tld.count) else { return false }

        let tldPattern = "^[A-Za-z]{2,10}$"
        guard tld.range(of: tldPattern, options: .regularExpression) != nil else { return false }

        let domainPattern = "^[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]$"
        for component in components.dropLast() {
            if component.count < 1 ||
                component.range(of: domainPattern, options: .regularExpression) == nil {
                return false
            }
        }

        return true
    }
}

extension CategoryClassifier: @unchecked Sendable {}
