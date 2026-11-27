import AppKit
import UniformTypeIdentifiers

/// One in-memory copy of every original representation, including app-specific types.
/// Restore only when the caller still owns the clipboard revision it intends to replace.
struct PasteboardSnapshot {
    private static let externalUTF16 = NSPasteboard.PasteboardType(UTType.utf16ExternalPlainText.identifier)

    let items: [[NSPasteboard.PasteboardType: Data]]

    @MainActor
    init?(pasteboard: NSPasteboard, changeCount: Int) {
        guard pasteboard.changeCount == changeCount, let originals = pasteboard.pasteboardItems else { return nil }
        var captured: [[NSPasteboard.PasteboardType: Data]] = []
        for item in originals {
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = Self.representation(type, in: item) else { return nil }
                contents[type] = data
            }
            captured.append(contents)
        }
        guard pasteboard.changeCount == changeCount else { return nil }
        items = captured
    }

    @MainActor
    private static func representation(_ type: NSPasteboard.PasteboardType, in item: NSPasteboardItem) -> Data? {
        if let data = item.data(forType: type) { return data }
        // Some items advertise UTF-16 but only supply the equivalent UTF-8 plain text.
        guard type == externalUTF16, let utf8 = item.data(forType: .string),
              let text = String(validating: utf8, as: UTF8.self) else { return nil }
        return text.data(using: .utf16)
    }

    @MainActor
    func write(to pasteboard: NSPasteboard, shouldWrite: () -> Bool) -> Int {
        let entries = items.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        // Building thousands of items can take time. Check ownership immediately before the write.
        guard shouldWrite() else { return -1 }
        let revision = pasteboard.clearContents()
        guard pasteboard.changeCount == revision else { return -1 }
        if entries.isEmpty { return revision }
        return pasteboard.writeObjects(entries) ? revision : -1
    }
}
