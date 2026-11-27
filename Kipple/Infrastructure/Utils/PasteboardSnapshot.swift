import AppKit

/// One in-memory copy of every original representation, including app-specific types.
/// Restore only when the caller still owns the clipboard revision it intends to replace.
struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    @MainActor
    init?(pasteboard: NSPasteboard, changeCount: Int) {
        guard pasteboard.changeCount == changeCount, let originals = pasteboard.pasteboardItems else { return nil }
        var captured: [[NSPasteboard.PasteboardType: Data]] = []
        for item in originals {
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                contents[type] = data
            }
            captured.append(contents)
        }
        guard pasteboard.changeCount == changeCount else { return nil }
        items = captured
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
