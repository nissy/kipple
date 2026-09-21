import AppKit
import SwiftData
import XCTest
@testable import Kipple

@MainActor
final class ClipboardRichTextTests: XCTestCase {
    func testMultipleTextItemsKeepTheirOwnFormattingWhenRecopied() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let entries = ["First", "Second"].map { text in
            let entry = NSPasteboardItem()
            entry.setString(text, forType: .string)
            entry.setString("<b>\(text)</b>", forType: .html)
            return entry
        }
        pasteboard.writeObjects(entries)
        let richText = try XCTUnwrap(ClipboardRichText(pasteboard: pasteboard))
        let item = ClipItem(content: "First\nSecond", richText: richText)
        XCTAssertGreaterThanOrEqual(ClipboardRichText.write(item, to: pasteboard), 0)
        XCTAssertEqual(pasteboard.string(forType: .string), item.content)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        XCTAssertEqual(pasteboard.pasteboardItems?.last?.string(forType: .html), "<b>Second</b>")
    }

    func testRecopyRestoresOriginalRichRepresentations() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let richText = try putStyledText(on: pasteboard, color: .systemRed)
        let item = ClipItem(content: "Styled text", richText: richText)
        let repository = MockClipboardRepository()
        let service = ModernClipboardService(testRepository: repository) { item in
            ClipboardRichText.write(item, to: pasteboard)
        }
        pasteboard.clearContents()
        await service.recopyFromHistory(item)
        XCTAssertEqual(pasteboard.string(forType: .string), item.content)
        XCTAssertEqual(ClipboardRichText(pasteboard: pasteboard), richText)
        let restored = try XCTUnwrap(NSAttributedString(rtf: XCTUnwrap(pasteboard.data(forType: .rtf)), documentAttributes: nil))
        let font = try XCTUnwrap(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testRichTextSurvivesPersistenceAndUpdate() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([ClipItemModel.self, MCPReceiptModel.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("history.store"))
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let repository = try SwiftDataRepository.make(container: container)
        var item = ClipItem(content: "Styled text", richText: try putStyledText(on: pasteboard, color: .systemRed))
        try await repository.save([item])
        item.richText = try putStyledText(on: pasteboard, color: .systemBlue)
        try await repository.update(item)
        let reopened = try SwiftDataRepository.make(
            container: ModelContainer(for: schema, configurations: [configuration])
        )
        let loaded = try await reopened.loadAll()
        XCTAssertEqual(loaded.first?.richText, item.richText)
        XCTAssertEqual(loaded.first?.content, item.content)
        item.richText = nil
        try await reopened.update(item)
        let cleared = try await repository.loadAll()
        XCTAssertNil(cleared.first?.richText)
    }

    func testLegacyHistoryWithoutRichTextStillDecodes() throws {
        let item = ClipItem(content: "Existing history")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        legacy.removeValue(forKey: "richText")
        let decoded = try JSONDecoder().decode(ClipItem.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.content, item.content)
        XCTAssertNil(decoded.richText)
        XCTAssertNil(ClipItemModel(from: item).toClipItem().richText)
    }

    func testMonitoringStoresLatestFormattingForTheSameText() async throws {
        let service = ModernClipboardService(testRepository: MockClipboardRepository())
        await service.startMonitoring()
        let red = try putStyledText(on: .general, color: .systemRed)
        await waitForFormatting(red, service: service)
        let first = await service.getHistory()
        let blue = try putStyledText(on: .general, color: .systemBlue)
        await waitForFormatting(blue, service: service)
        let updated = await service.getHistory()
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated.first?.id, first.first?.id)
        XCTAssertEqual(updated.first?.richText, blue)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Styled text", forType: .string)
        await waitForFormatting(nil, service: service)
        let plain = await service.getHistory()
        XCTAssertNil(plain.first?.richText, "A later plain-text copy must not inherit stale formatting")
        await service.stopMonitoring()
    }

    func testRepeatedPlainTextPasteKeepsHistoryFormattingForRecopy() async throws {
        let service = ModernClipboardService(testRepository: MockClipboardRepository())
        await service.startMonitoring()
        let richText = try putStyledText(on: .general, color: .systemRed)
        let controller = makePlainTextController(service: service)
        for _ in 0..<3 {
            controller.paste(into: 101)
            await controller.waitForPendingPastes()
            try? await Task.sleep(for: .milliseconds(300))
        }
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.richText, richText)
        XCTAssertNil(ClipboardRichText(pasteboard: .general))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Styled text")
        await service.recopyFromHistory(try XCTUnwrap(history.first))
        XCTAssertEqual(ClipboardRichText(pasteboard: .general), richText)
        await service.stopMonitoring()
    }

    func testFirstPlainTextPasteAfterStartupPreservesExistingClipboard() async throws {
        let richText = try putStyledText(on: .general, color: .systemRed)
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), loadOnStartup: true)
        await service.startMonitoring()
        let controller = makePlainTextController(service: service)
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        let history = await service.getHistory()
        XCTAssertEqual(history.first?.richText, richText)
        XCTAssertNil(ClipboardRichText(pasteboard: .general))
        await service.recopyFromHistory(try XCTUnwrap(history.first))
        XCTAssertEqual(ClipboardRichText(pasteboard: .general), richText)
        await service.stopMonitoring()
    }

    func testUnchangedEditorCopyPreservesFormattingButEditedTextClearsIt() async throws {
        let service = ModernClipboardService(testRepository: MockClipboardRepository())
        let richText = try putStyledText(on: .general, color: .systemRed)
        await service.writeToClipboardOnly("Styled text")
        XCTAssertEqual(ClipboardRichText(pasteboard: .general), richText)
        await service.writeToClipboardOnly("Edited text")
        XCTAssertNil(ClipboardRichText(pasteboard: .general))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Edited text")
    }

    private func makePlainTextController(service: ModernClipboardService) -> PlainTextPasteController {
        PlainTextPasteController(
            clipboardService: ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false),
            isTargetActive: { _ in true }, sendPaste: { _ in true }
        )
    }

    private func putStyledText(on pasteboard: NSPasteboard, color: NSColor) throws -> ClipboardRichText {
        let text = NSAttributedString(string: "Styled text", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: color
        ])
        let rtf = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf
        ])
        pasteboard.clearContents()
        pasteboard.setString(text.string, forType: .string)
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setString("<b>Styled text</b>", forType: .html)
        return try XCTUnwrap(ClipboardRichText(pasteboard: pasteboard))
    }

    private func waitForFormatting(_ richText: ClipboardRichText?, service: ModernClipboardService) async {
        for _ in 0..<100 {
            let history = await service.getHistory()
            if history.first?.content == "Styled text", history.first?.richText == richText { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Clipboard formatting was not captured")
    }
}
