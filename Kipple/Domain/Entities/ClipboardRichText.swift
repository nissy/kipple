import AppKit

/// Original text representations, kept separately from Kipple's display text.
struct ClipboardRichText: Codable, Equatable, Sendable {
    let text: String
    let items: [[String: Data]]

    private static let supportedTypes: [NSPasteboard.PasteboardType] = [.rtf, .rtfd, .html]

    @MainActor
    init?(pasteboard: NSPasteboard) {
        guard let text = pasteboard.string(forType: .string),
              let entries = pasteboard.pasteboardItems else { return nil }
        var items: [[String: Data]] = []
        var hasFormatting = false
        for entry in entries {
            guard let plainText = entry.string(forType: .string) else { return nil }
            var data = [NSPasteboard.PasteboardType.string.rawValue: Data(plainText.utf8)]
            for type in Self.supportedTypes {
                if let value = entry.data(forType: type) {
                    data[type.rawValue] = value
                    hasFormatting = true
                }
            }
            items.append(data)
        }
        guard hasFormatting else { return nil }
        self.text = text
        self.items = items
    }

    @MainActor
    static func write(
        _ item: ClipItem, to pasteboard: NSPasteboard, shouldWrite: () -> Bool = { true }
    ) -> Int {
        let entries: [NSPasteboardItem]
        if let richText = item.richText, richText.text == item.content, !richText.items.isEmpty {
            entries = richText.items.map { data in
                let entry = NSPasteboardItem()
                for type in supportedTypes + [.string] {
                    if let value = data[type.rawValue] { entry.setData(value, forType: type) }
                }
                return entry
            }
        } else {
            let entry = NSPasteboardItem()
            guard entry.setString(item.content, forType: .string) else { return -1 }
            entries = [entry]
        }
        // Preparing rich representations may be expensive; recheck ownership immediately before writing.
        guard shouldWrite() else { return -1 }
        pasteboard.clearContents()
        return pasteboard.writeObjects(entries) ? pasteboard.changeCount : -1
    }
}
