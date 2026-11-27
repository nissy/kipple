import AppKit
import SwiftUI

struct DesktopNoteLongText: NSViewRepresentable {
    static let sizingCharacterLimit = 2_048

    let text: String
    let font: NSFont
    let onHeightChange: (CGFloat) -> Void

    static func content(for text: String, displayMode: AppSettings.DesktopNoteDisplayMode) -> String? {
        guard text.utf16.count > sizingCharacterLimit else { return nil }
        if displayMode == .plainText { return text }

        // Keep structured Markdown in Textual. A literal paragraph needs no rich rendering.
        guard let markdown = try? AttributedString(markdown: text), markdown.runs.count == 1,
              let run = markdown.runs.first, run.link == nil, run.imageURL == nil,
              run.inlinePresentationIntent == nil, let components = run.presentationIntent?.components,
              components.count == 1, case .paragraph = components[0].kind,
              markdown.characters.elementsEqual(text) else { return nil }
        return text
    }

    func makeNSView(context: Context) -> ScrollView {
        let scroll = ScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        // TextKit 1 can lay out the visible range without measuring an entire unbroken paragraph.
        let view = NSTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.layoutManager?.allowsNonContiguousLayout = true
        view.textContainerInset = NSSize(width: HistoryItemPreviewContent.contentPadding, height: 0)
        view.setAccessibilityLabel(AppSettings.shared.localizedString("Content"))
        let hitView = DesktopNoteTextHitView(frame: view.bounds)
        hitView.allowsSelectionMargin = true
        hitView.autoresizingMask = [.width, .height]
        view.addSubview(hitView)
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: ScrollView, context: Context) {
        scroll.onHeightChange = onHeightChange
        guard let view = scroll.documentView as? NSTextView,
              view.font != font || !view.string.utf8.elementsEqual(text.utf8) else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
        ]))
    }

    final class ScrollView: NSScrollView {
        var onHeightChange: (CGFloat) -> Void = { _ in }
        private var lastHeight: CGFloat = 0

        override func reflectScrolledClipView(_ clip: NSClipView) {
            super.reflectScrolledClipView(clip)
            guard let height = documentView?.frame.height, height > 0, height != lastHeight else { return }
            lastHeight = height
            onHeightChange(height + 8)
        }
    }
}

@MainActor
final class DesktopNoteTextHitView: NSView {
    private static let horizontalSelectionMargin: CGFloat = 12
    private static let verticalSelectionMargin: CGFloat = 4
    var lines: [CGRect] = []
    var allowsSelectionMargin = false

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? DesktopNotePanel)?.registerTextHitView(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func textLines(at point: NSPoint) -> [CGRect] {
        guard let view = superview as? NSTextView,
              let layout = view.layoutManager, let container = view.textContainer else { return lines }
        let origin = view.textContainerOrigin
        let dy = Self.verticalSelectionMargin
        let rect = CGRect(x: 0, y: point.y - origin.y - dy, width: bounds.width, height: 2 * dy)
        let glyphs = layout.glyphRange(forBoundingRect: rect, in: container)
        var visibleLines: [CGRect] = []
        layout.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
            visibleLines.append(used.offsetBy(dx: origin.x, dy: origin.y))
        }
        return visibleLines
    }

    func containsText(at windowPoint: NSPoint) -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
        let point = convert(windowPoint, from: nil)
        return visibleRect.contains(point) && textLines(at: point).contains { $0.contains(point) }
    }

    func nearbySelectionStart(at windowPoint: NSPoint) -> NSPoint? {
        guard allowsSelectionMargin, window != nil, !isHiddenOrHasHiddenAncestor else { return nil }
        if let clip = enclosingScrollView?.contentView,
           !clip.visibleRect.contains(clip.convert(windowPoint, from: nil)) { return nil }
        let point = convert(windowPoint, from: nil)
        let visible = visibleRect
        let dx = Self.horizontalSelectionMargin
        let dy = Self.verticalSelectionMargin
        guard visible.insetBy(dx: -dx, dy: -dy).contains(point) else { return nil }

        var nearest: NSPoint?
        var nearestDistance = CGFloat.infinity
        for line in textLines(at: point) where line.insetBy(dx: -dx, dy: -dy).contains(point) {
            let clipped = line.intersection(visible)
            guard !clipped.isEmpty else { continue }
            let selectable = clipped.insetBy(dx: min(0.5, clipped.width / 4), dy: 0.5)
            guard !selectable.isEmpty else { continue }
            let start = NSPoint(x: min(max(point.x, selectable.minX), selectable.maxX),
                                y: min(max(point.y, selectable.minY), selectable.maxY))
            let distance = hypot(point.x - start.x, point.y - start.y)
            if distance < nearestDistance {
                nearest = start
                nearestDistance = distance
            }
        }
        return nearest.map { convert($0, to: nil) }
    }
}
