import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Kipple

@MainActor
final class DesktopNoteLayoutTests: XCTestCase {
    private let screenFrame = NSRect(x: 0, y: 0, width: 900, height: 700)

    func testNoteRendersAnOpaqueBackgroundInLightAndDarkAppearances() throws {
        let note = DesktopNotePanel(item: ClipItem(content: "Short note"), screenFrame: screenFrame)
        note.setContentSize(NSSize(width: 260, height: 160))
        defer { note.close() }
        let content = try XCTUnwrap(note.contentView)
        note.appearance = NSAppearance(named: .aqua)
        let light = try renderNoteBackground(in: content)
        let strip = note.colorStrip
        XCTAssertTrue(DesktopNoteColor.palette.contains(note.selectedColor))
        XCTAssertFalse(strip.isHidden)

        let orange = NSMenuItem()
        orange.representedObject = "Orange Note Color"
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("changeColor:"), to: note, from: orange))
        XCTAssertEqual(strip.layer?.backgroundColor, NSColor.systemOrange.cgColor)

        note.appearance = NSAppearance(named: .darkAqua)
        let dark = try renderNoteBackground(in: content)
        XCTAssertEqual(light.alphaComponent, 1)
        XCTAssertEqual(dark.alphaComponent, 1)
        XCTAssertGreaterThan(light.redComponent, dark.redComponent)
        XCTAssertEqual(strip.alphaValue, 1)
        XCTAssertEqual(strip.layer?.backgroundColor?.alpha, 1)
        XCTAssertFalse(strip.isHidden)

        let none = NSMenuItem()
        none.representedObject = "No Note Color"
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("changeColor:"), to: note, from: none))
        XCTAssertTrue(strip.isHidden)
    }

    func testColorMenuOffersThe16HTMLColorsAndSavesTheSelection() throws {
        let expected: [DesktopNoteColor: Int] = [
            .black: 0x000000, .silver: 0xC0C0C0, .gray: 0x808080, .white: 0xFFFFFF,
            .maroon: 0x800000, .red: 0xFF0000, .purple: 0x800080, .fuchsia: 0xFF00FF,
            .green: 0x008000, .lime: 0x00FF00, .olive: 0x808000, .yellow: 0xFFFF00,
            .navy: 0x000080, .blue: 0x0000FF, .teal: 0x008080, .aqua: 0x00FFFF
        ]
        let note = DesktopNotePanel(item: ClipItem(content: "Color sample"), screenFrame: screenFrame)
        defer { note.close() }
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let itemID = UUID()
        note.onPlacementChange = { [weak note] in
            guard let note else { return }
            DesktopNotePlacement.save([itemID: note.placement], to: defaults)
        }
        let action = NSSelectorFromString("changeColor:")
        let menu = note.noteContentController.makeColorMenu(selected: .aqua, target: note, action: action)
        let items = menu.items.filter { !$0.isSeparatorItem }
        let colors = items.compactMap { ($0.representedObject as? String).flatMap(DesktopNoteColor.init(rawValue:)) }
        XCTAssertEqual(items.count, 17)
        XCTAssertEqual(Set(colors.dropLast()), Set(expected.keys))
        XCTAssertEqual(colors.last, DesktopNoteColor.none)

        for (item, color) in zip(items.dropLast(), colors.dropLast()) {
            let fill = try XCTUnwrap(color.fill)
            XCTAssertNotNil(item.image)
            if #available(macOS 27.0, *) { XCTAssertEqual(item.preferredImageVisibility, .visible) }
            XCTAssertEqual(item.state, color == .aqua ? .on : .off)
            let rgb = [fill.redComponent, fill.greenComponent, fill.blueComponent]
                .reduce(0) { ($0 << 8) | Int(($1 * 255).rounded()) }
            XCTAssertEqual(rgb, expected[color])
            XCTAssertTrue(NSApp.sendAction(action, to: note, from: item))
            XCTAssertEqual(note.colorStrip.layer?.backgroundColor, fill.cgColor)
            XCTAssertEqual(DesktopNotePlacement.load(from: defaults)[itemID]?.color, color)
        }
    }

    private func renderNoteBackground(in content: NSView) throws -> NSColor {
        content.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let sample = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
        return try XCTUnwrap(sample?.usingColorSpace(.deviceRGB))
    }

    func testNoteFitsShortAndWrappedContentAndCapsInitialHeight() {
        let short = DesktopNotePanel(item: ClipItem(content: "Short note"), screenFrame: screenFrame)
        let wrapped = DesktopNotePanel(
            item: ClipItem(content: String(repeating: "Text that wraps across lines. ", count: 7)),
            screenFrame: screenFrame
        )
        let long = DesktopNotePanel(
            item: ClipItem(content: String(repeating: "Another line\n", count: 90)),
            screenFrame: screenFrame
        )
        defer {
            [short, wrapped, long].forEach { $0.close() }
        }

        XCTAssertLessThan(short.frame.width, wrapped.frame.width)
        XCTAssertLessThan(short.frame.height, wrapped.frame.height)
        XCTAssertLessThan(wrapped.frame.height, long.frame.height)
        XCTAssertEqual(long.frame.height, screenFrame.height)
        XCTAssertTrue(short.title.isEmpty)
        XCTAssertEqual(short.titleVisibility, .hidden)
    }

    func testMarkdownNoteFitsItsRenderedBodyWithoutMovingItsTopEdge() async throws {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let content = """
        # Work items

        ## Release

        | Item | Status |
        | --- | --- |
        | Review | Done |
        | Publish | Waiting |

        ```
        make run
        ```

        ## Next steps

        Follow up after the release.
        """
        var item = ClipItem(content: content)
        let note = DesktopNotePanel(item: item, screenFrame: screen, displayMode: .markdown)
        let topLeft = NSPoint(x: screen.minX + 40, y: screen.maxY - 40)
        note.setFrameTopLeftPoint(topLeft)
        let estimatedHeight = note.frame.height
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }

        let view = try XCTUnwrap(note.contentView)
        let clip = try XCTUnwrap(firstScrollView(in: view)).contentView
        for _ in 0..<50 {
            if note.frame.height > estimatedHeight,
               clip.documentRect.height <= clip.bounds.height + 1,
               let table = firstScrollView(in: clip)?.contentView,
               table.documentRect.width <= table.bounds.width + 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(note.frame.height, estimatedHeight)
        XCTAssertGreaterThan(clip.documentRect.height, 150)
        XCTAssertLessThanOrEqual(clip.documentRect.height, clip.bounds.height + 1)
        let table = try XCTUnwrap(firstScrollView(in: clip)).contentView
        XCTAssertLessThanOrEqual(table.documentRect.width, table.bounds.width + 1)
        XCTAssertEqual(note.frame.minX, topLeft.x)
        XCTAssertEqual(note.frame.maxY, topLeft.y)

        item = item.replacingContent(with: "[Open](https://example.com/\(String(repeating: "a", count: 400)))")
        note.update(from: item)
        XCTAssertEqual(note.frame.width, note.minSize.width)
        XCTAssertEqual(note.frame.height, note.minSize.height)
        XCTAssertEqual(note.frame.maxY, topLeft.y)
    }

    func testRestoredAutomaticNoteKeepsItsSizeUntilTheContentChanges() async throws {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let text = (1...6).map { "## Step \($0)\n\nReview the release notes." }.joined(separator: "\n\n")
        let item = ClipItem(content: text)
        let note = DesktopNotePanel(item: item, screenFrame: screen, displayMode: .markdown) { _, _ in }
        let saved = NSRect(x: screen.minX + 40, y: screen.maxY - 220, width: 265, height: 180)
        note.restorePlacement(DesktopNotePlacement(frame: saved, color: .none, usesManualSize: false), in: screen)
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }

        let view = try XCTUnwrap(note.contentView)
        let clip = try XCTUnwrap(firstScrollView(in: view)).contentView
        for _ in 0..<50 where clip.documentRect.height <= clip.bounds.height {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(clip.documentRect.height, clip.bounds.height)
        XCTAssertEqual(note.frame, saved)
        XCTAssertFalse(note.placement.usesManualSize)

        try desktopNoteEditButton(in: note).performClick(nil)
        let editor = try XCTUnwrap(note.firstResponder as? LiveEditorTextView)
        editor.string = "Unsaved draft"
        let escape = try desktopNoteKeyEvent(kVK_Escape, characters: "\u{1B}", modifiers: [], for: note)
        note.sendEvent(escape)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(note.frame, saved)
        XCTAssertFalse(note.placement.usesManualSize)

        note.update(from: item.replacingContent(with: "Ready"))
        XCTAssertLessThan(note.frame.height, saved.height)
        XCTAssertEqual(note.frame.maxY, saved.maxY)
    }

    func testMovingAScreenLimitedNoteUpGivesTheBodyMoreSpace() async throws {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let item = ClipItem(content: "Follow-up")
        let note = DesktopNotePanel(item: item, screenFrame: screen)
        let top = NSPoint(x: screen.minX + 75, y: screen.minY + 175)
        note.setFrameTopLeftPoint(top)
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }

        note.update(from: item.replacingContent(with: (1...20).map { "Item \($0)" }.joined(separator: "\n")))
        let view = try XCTUnwrap(note.contentView)
        let clip = try XCTUnwrap(firstScrollView(in: view)).contentView
        try await Task.sleep(for: .milliseconds(100))
        let before = note.frame
        XCTAssertEqual(before.minY, screen.minY)
        XCTAssertGreaterThan(clip.documentRect.height, clip.bounds.height)

        let start = NSPoint(x: before.width - 32, y: before.height - 48)
        let distance = screen.maxY - 40 - top.y
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: NSPoint(x: start.x, y: start.y + distance), for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: start, for: note))

        XCTAssertGreaterThan(note.frame.height, before.height)
        XCTAssertEqual(note.frame.minX, before.minX)
        XCTAssertEqual(note.frame.maxY, screen.maxY - 40)
        XCTAssertFalse(note.placement.usesManualSize)
    }

    func testFitToContentMenuResumesAutomaticSizing() async throws {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let item = ClipItem(content: "Short note")
        let note = DesktopNotePanel(item: item, screenFrame: screen)
        defer { note.close() }
        let saved = NSRect(x: screen.minX + 75, y: screen.maxY - 280, width: 295, height: 200)
        note.restorePlacement(DesktopNotePlacement(frame: saved, color: .yellow, usesManualSize: true), in: screen)
        note.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(50))

        let text = try desktopNoteBodyPoint(in: note, x: 29)
        XCTAssertNil(note.automaticSizeMenu(at: text))
        let blank = NSPoint(x: 120, y: 65)
        let menu = try XCTUnwrap(note.automaticSizeMenu(at: blank))
        XCTAssertEqual(menu.items.first?.title, AppSettings.shared.localizedString("Fit Note to Content"))
        menu.performActionForItem(at: 0)

        XCTAssertFalse(note.placement.usesManualSize)
        XCTAssertEqual(note.placement.color, .yellow)
        XCTAssertEqual(note.frame.minX, saved.minX)
        XCTAssertEqual(note.frame.maxY, saved.maxY)
        XCTAssertLessThan(note.frame.height, saved.height)
        XCTAssertNil(note.automaticSizeMenu(at: blank))

        let height = note.frame.height
        note.update(from: item.replacingContent(with: String(repeating: "Longer note content.\n", count: 12)))
        XCTAssertGreaterThan(note.frame.height, height)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = firstScrollView(in: child) { return scrollView }
        }
        return nil
    }

    func testNoteDisplaysTheHistoryTitle() {
        let title = "Review notes for the desktop release"
        let item = ClipItem(content: "Short note", metadata: ClipMetadata(title: title))
        let note = DesktopNotePanel(item: item, screenFrame: screenFrame)
        let untitled = DesktopNotePanel(item: ClipItem(content: "Short note"), screenFrame: screenFrame)
        defer {
            note.close()
            untitled.close()
        }

        XCTAssertEqual(note.title, title)
        XCTAssertGreaterThan(note.frame.height, untitled.frame.height)
    }

    func testManuallyResizedNoteKeepsSizeWhenItsContentOrDisplayModeChanges() throws {
        var item = ClipItem(content: "Short note")
        let note = DesktopNotePanel(item: item, screenFrame: screenFrame)
        note.setFrameTopLeftPoint(NSPoint(x: 40, y: 600))
        defer { note.close() }

        let start = note.frame
        simulateDesktopNoteLiveResize(note, to: NSSize(width: start.width + 120, height: start.height + 160))
        let resized = note.frame
        XCTAssertEqual(resized.width, start.width + 120)
        XCTAssertEqual(resized.height, start.height + 160)
        XCTAssertEqual(resized.minX, start.minX)
        XCTAssertEqual(resized.maxY, start.maxY)

        item = item.replacingContent(with: String(repeating: "A longer note body.\n\n", count: 120))
        note.update(from: item)
        XCTAssertEqual(note.frame, resized)

        let stack = try XCTUnwrap(note.contentView?.subviews.compactMap { $0 as? NSStackView }.first)
        let showMarkdown = AppSettings.shared.localizedString("Show Markdown")
        let button = try XCTUnwrap(stack.views.compactMap { $0 as? NSButton }.first { $0.toolTip == showMarkdown })
        button.performClick(nil)
        XCTAssertEqual(note.frame, resized)
    }

    func testManuallyResizedNoteReservesReadingSpaceWhenATitleIsAdded() {
        var item = ClipItem(content: "Note body")
        let note = DesktopNotePanel(item: item, screenFrame: screenFrame)
        note.setFrameTopLeftPoint(NSPoint(x: 40, y: 600))
        defer { note.close() }

        note.setContentSize(NSSize(width: 240, height: 160))
        simulateDesktopNoteLiveResize(note, to: note.minSize)
        let untitled = note.frame
        XCTAssertEqual(untitled.height, 86)

        item.metadata = ClipMetadata(title: "A long history title that wraps onto two lines")
        note.update(from: item)
        let titled = note.frame
        XCTAssertGreaterThan(titled.height, untitled.height)
        XCTAssertEqual(titled.width, untitled.width)
        XCTAssertEqual(titled.maxY, untitled.maxY)

        XCTAssertEqual(titled.height, note.minSize.height)
    }
}
