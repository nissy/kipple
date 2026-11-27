import AppKit
import ApplicationServices

extension ClipboardReader {
    struct ComparisonInput: Sendable {
        let text: String
        let bundleID: String?
        let webPageURL: URL?
        let windowBounds: CGRect?
        var listMarkers: Set<Character> = []

        var hasEmbeddedObjects: Bool { text.unicodeScalars.contains("\u{FFFC}") }

        func matches(_ copy: Snapshot) -> Bool {
            guard let copiedText = copy.text, !copiedText.isEmpty else { return false }
            if copy.hasSourceDeclaration, bundleID == nil || copy.source?.bundleID != bundleID { return false }
            if let webPageURL, let sourceURI = copy.sourceURI,
               URL(string: sourceURI, encodingInvalidCharacters: false) != webPageURL { return false }
            // AX may drop whitespace. This check attributes the write; the diff uses native copy output.
            let selectedBody = text.filter { !$0.isWhitespace }
            if copiedText.utf8.elementsEqual(text.utf8)
                || (!selectedBody.isEmpty && selectedBody.utf8.elementsEqual(copiedText.filter { !$0.isWhitespace }.utf8)) {
                return true
            }
            guard !listMarkers.isEmpty, let webPageURL, let sourceURI = copy.sourceURI,
                  URL(string: sourceURI, encodingInvalidCharacters: false) == webPageURL else { return false }
            let selectedLines = text.split(whereSeparator: \.isNewline)
            let listBodies = selectedLines.map { line in
                var body = line.drop(while: \.isWhitespace)
                if let first = body.first, listMarkers.contains(first) {
                    body = body.dropFirst()
                }
                let trimmed = body.filter { !$0.isWhitespace }
                // Some accessibility trees put a separate list marker at the end of the preceding line.
                if let last = trimmed.last, listMarkers.contains(last), ClipboardReader.isPrivateUseMarker(last) {
                    return String(trimmed.dropLast())
                }
                return trimmed
            }
            let selectedBodies = listBodies.filter { !$0.isEmpty }
            let copiedBodies = copiedText
                .split(whereSeparator: \.isNewline)
                .map { $0.filter { !$0.isWhitespace } }
                .filter { !$0.isEmpty }
            return !selectedBodies.isEmpty && selectedBodies.elementsEqual(copiedBodies) { $0.utf8.elementsEqual($1.utf8) }
        }
    }

    static func comparisonInput(in target: NSRunningApplication) async -> ComparisonInput? {
        let processID = target.processIdentifier
        let bundleID = target.bundleIdentifier
        let input = await Task.detached(priority: .userInitiated) { () -> ComparisonInput? in
            let app = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(app, 0.10)
            let window = accessibilityElement(kAXFocusedWindowAttribute, on: app)
            guard let focused = accessibilityElement(kAXFocusedUIElementAttribute, on: app),
                  let selection = selectedText(on: focused), !selection.isEmpty else { return nil }
            let decorations = listDecorations(in: selection, on: focused)
            let url = decorations.isEmpty ? webPageURL(on: focused) : enclosingPageURL(on: focused)
            let bounds = window.flatMap { windowBounds(on: $0) }
            guard window == accessibilityElement(kAXFocusedWindowAttribute, on: app),
                  focused == accessibilityElement(kAXFocusedUIElementAttribute, on: app) else { return nil }
            return ComparisonInput(
                text: selection, bundleID: bundleID, webPageURL: url, windowBounds: bounds, listMarkers: decorations
            )
        }.value
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return nil }
        return input
    }

    private nonisolated static func listDecorations(in text: String, on element: AXUIElement) -> Set<Character> {
        let candidates = Set(text.filter { "•◦▪".contains($0) || isPrivateUseMarker($0) })
        guard !candidates.isEmpty, let range = selectedRange(on: element) else { return [] }
        let start = selectionAncestors(of: AXTextMarkerRangeCopyStartMarker(range), on: element)
        let end = selectionAncestors(of: AXTextMarkerRangeCopyEndMarker(range), on: element)
        guard let list = start.first(where: {
            end.contains($0) && accessibilityValue(kAXRoleAttribute, on: $0) as? String == kAXListRole
        }) else { return [] }
        var markers = candidates.filter { !isPrivateUseMarker($0) }
        guard markers != candidates else { return markers }

        // Only consider a private-use glyph when the list exposes it as a separate accessibility node.
        let deadline = ProcessInfo.processInfo.systemUptime + 0.10
        var pending = [list]
        var visited = 0
        while let node = pending.popLast(), visited < 96, ProcessInfo.processInfo.systemUptime < deadline {
            visited += 1
            guard let children = accessibilityChildren(of: node) else { return [] }
            pending.append(contentsOf: children)
            if children.isEmpty, let value = accessibilityValue(kAXValueAttribute, on: node) as? String,
               value.count == 1, let glyph = value.first, candidates.contains(glyph), isPrivateUseMarker(glyph) {
                markers.insert(glyph)
            }
        }
        return markers
    }

    private nonisolated static func isPrivateUseMarker(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && character.unicodeScalars.first?.properties.generalCategory == .privateUse
    }

    private nonisolated static func enclosingPageURL(on element: AXUIElement) -> URL? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.10
        var current: AXUIElement? = element
        for _ in 0..<32 {
            guard let node = current, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            if let url = webPageURL(on: node) { return url }
            current = accessibilityElement(kAXParentAttribute, on: node)
        }
        return nil
    }

    private nonisolated static func windowBounds(on element: AXUIElement) -> CGRect? {
        guard let position = accessibilityValue(kAXPositionAttribute, on: element),
              let size = accessibilityValue(kAXSizeAttribute, on: element),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
}
