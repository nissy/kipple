import Foundation

struct ClipMetadata: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case clipboard, editor, ocr, mcp, unknown
    }

    var title: String?
    var createdAt: Date?
    var source: Source = .unknown

    func inheritingDetails(from previous: ClipMetadata?) -> ClipMetadata {
        guard let previous else { return self }
        var result = self
        result.title = title ?? previous.title
        result.createdAt = previous.createdAt ?? createdAt
        return result
    }
}

extension ClipItem {
    var title: String? { metadata?.title }

    func matchesSearch(_ query: String) -> Bool {
        (title?.localizedCaseInsensitiveContains(query) ?? false) ||
        (sourceApp?.localizedCaseInsensitiveContains(query) ?? false) ||
        content.localizedCaseInsensitiveContains(query)
    }
}
