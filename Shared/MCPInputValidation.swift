import Foundation

enum MCPInputValidation {
    static func decode(_ data: Data) throws -> MCPRegistration {
        guard data.count <= MCPProtocolConfig.maxInputBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["requestId", "items"]),
              let items = object["items"] as? [[String: Any]],
              (1...50).contains(items.count) else { throw MCPFailure.invalidInput }
        let keys: Set<String> = ["content", "title"]
        for item in items {
            guard Set(item.keys).isSubset(of: keys),
                  let content = item["content"] as? String else {
                throw MCPFailure.invalidInput
            }
            _ = try text(content)
        }
        return try JSONDecoder().decode(MCPRegistration.self, from: data)
    }

    static func title(_ title: String?) throws -> String? {
        guard let title else { return nil }
        guard title.unicodeScalars.count <= 120, !title.contains("\0") else { throw MCPFailure.invalidInput }
        let normalized = title.components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func text(_ content: String) throws -> String {
        guard !content.isEmpty, !content.contains("\0") else { throw MCPFailure.invalidInput }
        // JSON Schema maxLength counts Unicode code points, not UTF-8 bytes or grapheme clusters.
        guard content.unicodeScalars.count <= MCPProtocolConfig.maxTextCharacters else { throw MCPFailure.tooLarge }
        return content
    }
}
