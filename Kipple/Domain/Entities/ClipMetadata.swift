import Foundation

struct ClipMetadata: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case clipboard, editor, ocr, mcp, unknown
    }

    var title: String?
    var createdAt: Date?
    var source: Source = .unknown
    var recordedSources: Set<Source>?
    var categoryOverrides: CategoryOverrides?

    var sources: Set<Source> { (recordedSources ?? []).union([source]) }

    func inheritingDetails(from previous: ClipMetadata?) -> ClipMetadata {
        guard let previous else { return self }
        var result = self
        result.title = title ?? previous.title
        result.createdAt = previous.createdAt ?? createdAt
        let combinedSources = sources.union(previous.sources)
        result.recordedSources = combinedSources.count > 1 ? combinedSources : nil
        result.categoryOverrides = previous.categoryOverrides ?? categoryOverrides
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
