import AppKit
import XCTest
@testable import Kipple

@MainActor
final class ClipboardReaderImageTests: XCTestCase {
    private let chromiumSourceType = NSPasteboard.PasteboardType("org.chromium.source-url")

    func testVerifiedImageAlternativeTextRecordsSourceInHistory() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let page = try XCTUnwrap(URL(string: "https://example.com/documents/page"))
        let image = try XCTUnwrap(URL(string: "https://example.com/documents/photos/one.png"))
        let copied = "Before Cats & dogs 写真 After"
        let html = #"<p>Before <img src="photos/one.png" alt="Cats &amp; dogs &#x5199;&#x771f;"> After</p>"#
        let selection = imageSelection(text: "Before \u{FFFC} After", page: page, urls: [image])
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, sourcePage in
            XCTAssertEqual(sourcePage, page)
            return selection
        })
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository, clipboardReader: reader)
        let archive = try PropertyListSerialization.data(
            fromPropertyList: ["WebMainResource": ["WebResourceURL": page.absoluteString]],
            format: .binary,
            options: 0
        )
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(copied, forType: .string))
        XCTAssertTrue(pasteboard.setString(html, forType: .html))
        XCTAssertTrue(pasteboard.setData(archive, forType: NSPasteboard.PasteboardType("com.apple.webarchive")))
        await service.checkClipboardForTesting()
        await service.flushPendingSaves()

        let history = try await repository.loadAll()
        let item = try XCTUnwrap(history.first)
        XCTAssertEqual(item.content, copied)
        XCTAssertEqual(item.sourceApp, "Example Browser")
        XCTAssertEqual(item.windowTitle, "Example Window")
        XCTAssertEqual(item.metadata?.sourceURI, page.absoluteString)
    }

    func testImageSelectionRejectsMissingDifferentOrReorderedURLsAndDifferentBody() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let page = try XCTUnwrap(URL(string: "https://example.com/page"))
        let otherPage = try XCTUnwrap(URL(string: "https://example.com/other-page"))
        let first = try XCTUnwrap(URL(string: "https://example.com/first/photo.png"))
        let second = try XCTUnwrap(URL(string: "https://example.com/second/photo.png"))
        let third = try XCTUnwrap(URL(string: "https://example.com/third/photo.png"))
        let copied = "Before photo between photo After"
        let html = #"<p>Before <img src="/first/photo.png" alt="photo"> between <img src="/second/photo.png" alt="photo"> After</p>"#
        let text = "Before \u{FFFC} between \u{FFFC} After"
        let cases = [
            imageSelection(text: text, page: page, urls: nil),
            imageSelection(text: text, page: page, urls: [first]),
            imageSelection(text: text, page: page, urls: [first, third]),
            imageSelection(text: text, page: page, urls: [second, first]),
            imageSelection(text: text, page: otherPage, urls: [first, second]),
            imageSelection(text: "Other \u{FFFC} between \u{FFFC} After", page: page, urls: [first, second]),
            imageSelection(text: copied, page: page, urls: [first, third])
        ]
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(copied, forType: .string))
        XCTAssertTrue(pasteboard.setString(html, forType: .html))
        XCTAssertTrue(pasteboard.setString(page.absoluteString, forType: chromiumSourceType))
        for selection in cases {
            let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
                selection
            })
            let captured = await reader.readForHistory(changeCount: pasteboard.changeCount)
            XCTAssertEqual(captured?.text, copied)
            XCTAssertNil(captured?.source)
        }
        let selection = imageSelection(text: text, page: page, urls: [first, second])
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
            selection
        })
        let captured = await reader.readForHistory(changeCount: pasteboard.changeCount)
        XCTAssertEqual(captured?.source?.windowTitle, "Example Window")
    }

    func testImageCopyWithoutSourcePageDoesNotInferAnAppFromMatchingText() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let copied = "Before After"
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(copied, forType: .string))
        XCTAssertTrue(pasteboard.setString(#"<img src="https://example.com/image.png" alt="">"#, forType: .html))
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
            self.imageSelection(text: copied, page: nil, urls: nil)
        })
        let captured = await reader.readForHistory(changeCount: pasteboard.changeCount)
        XCTAssertEqual(captured?.text, copied)
        XCTAssertNil(captured?.source)
    }

    private func imageSelection(text: String, page: URL?, urls: [URL]?) -> ClipboardReader.Selection {
        ClipboardReader.Selection(
            text: text,
            source: .init(
                name: "Example Browser", bundleID: "example.browser", processID: 123, windowTitle: "Example Window"
            ),
            webPageURL: page,
            imageURLs: urls
        )
    }
}
