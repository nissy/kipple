enum ClipboardTextLimit {
    static let maxCharacters = 80_000

    // Count Unicode code points, as in the MCP schema.
    static func allows(_ text: String) -> Bool {
        text.unicodeScalars.dropFirst(maxCharacters).isEmpty
    }
}
