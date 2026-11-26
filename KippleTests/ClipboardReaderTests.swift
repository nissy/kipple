import AppKit
import XCTest
@testable import Kipple

@MainActor
final class ClipboardReaderTests: XCTestCase {
    private let chromiumSourceType = NSPasteboard.PasteboardType("org.chromium.source-url")
    private let sourceBundleType = NSPasteboard.PasteboardType("org.nspasteboard.source")

    func testDeniedReadIsNotAttemptedAndUnchangedClipboardRecoversAfterGrant() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Allowed later", forType: .string)
        let count = pasteboard.changeCount
        var policy: NSPasteboard.AccessBehavior = .alwaysDeny
        var reads = 0
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { policy }, readText: {
            reads += 1
            return pasteboard.string(forType: .string)
        })
        let repository = MockClipboardRepository()
        let service = ModernClipboardService(testRepository: repository, clipboardReader: reader)
        await service.checkClipboardForTesting()
        await service.checkClipboardForTesting()
        XCTAssertEqual(reads, 0)
        let before = await service.getHistory()
        XCTAssertTrue(before.isEmpty)

        policy = .alwaysAllow
        await service.checkClipboardForTesting()
        let after = await service.getHistory()
        XCTAssertEqual(after.map(\.content), ["Allowed later"])
        XCTAssertEqual(pasteboard.changeCount, count)
        XCTAssertEqual(reads, 1)
    }

    func testFailedReadDoesNotRepeatUntilExplicitRetry() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("Retry me", forType: .string)
        var available = false
        var reads = 0
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .ask }, readText: {
            reads += 1
            return available ? "Retry me" : nil
        })
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        await service.checkClipboardForTesting()
        await service.checkClipboardForTesting()
        XCTAssertTrue(reader.readFailed)
        XCTAssertEqual(reads, 1)
        available = true
        XCTAssertEqual(reader.read(retry: true)?.text, "Retry me")
        await service.checkClipboardForTesting()
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), ["Retry me"])
        XCTAssertEqual(reads, 2)
        XCTAssertFalse(reader.readFailed)
    }

    func testSuccessfulFirstReadSurvivesDefaultPolicyChangingToAsk() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("First allowed read", forType: .string)
        var policy: NSPasteboard.AccessBehavior = .default
        var reads = 0
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { policy }, readText: {
            reads += 1
            policy = .ask
            return "First allowed read"
        })
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        await service.checkClipboardForTesting()
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), ["First allowed read"])
        XCTAssertEqual(reader.read()?.text, "First allowed read")
        XCTAssertEqual(reads, 1)
    }

    func testRevocationDropsCachedContentsAndGrantReadsAgain() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Private", forType: .string)
        var policy: NSPasteboard.AccessBehavior = .alwaysAllow
        let readAccess = { policy }
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: readAccess)
        XCTAssertEqual(reader.read()?.text, "Private")
        policy = .alwaysDeny
        XCTAssertNil(reader.read())
        policy = .alwaysAllow
        XCTAssertEqual(reader.read()?.text, "Private")
    }

    func testCopyDuringReadIsRetriedWithoutReturningMixedContent() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("First", forType: .string)
        pasteboard.setString("https://example.com/first", forType: chromiumSourceType)
        var reads = 0
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readText: { [chromiumSourceType] in
            reads += 1
            if reads == 1 {
                pasteboard.clearContents()
                pasteboard.setString("Second", forType: .string)
                pasteboard.setString("https://example.com/second", forType: chromiumSourceType)
                return "First"
            }
            return pasteboard.string(forType: .string)
        })
        XCTAssertNil(reader.read())
        XCTAssertEqual(reader.read()?.text, "Second")
        XCTAssertEqual(reader.read()?.sourceURI, "https://example.com/second")
    }

    func testHistoryPersistsSourceURIAndUpdatesItWithEachCopy() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard) { .alwaysAllow }
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository, clipboardReader: reader)
        let content = "Review this document"
        let sourceURL = "https://example.com/documents/one%20two#summary"
        let sourceURI = "slack://channel?team=T123&id=C456"

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(content, forType: .string))
        XCTAssertTrue(pasteboard.setString(sourceURL, forType: chromiumSourceType))
        await service.checkClipboardForTesting()
        await service.flushPendingSaves()
        let original = try await repository.loadAll()
        XCTAssertEqual(original.map(\.content), [content])
        XCTAssertEqual(original.first?.metadata?.sourceURI, sourceURL)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(content, forType: .string))
        XCTAssertTrue(pasteboard.setString(sourceURI, forType: chromiumSourceType))
        await service.checkClipboardForTesting()
        await service.flushPendingSaves()
        let updated = try await repository.loadAll()
        XCTAssertEqual(updated.map(\.id), original.map(\.id))
        XCTAssertEqual(updated.first?.metadata?.sourceURI, sourceURI)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(content, forType: .string))
        XCTAssertTrue(pasteboard.setString("https://example.com/copied-link", forType: .URL))
        await service.checkClipboardForTesting()
        await service.flushPendingSaves()
        let withoutSource = try await repository.loadAll()
        XCTAssertEqual(withoutSource.map(\.id), original.map(\.id))
        XCTAssertNil(withoutSource.first?.metadata?.sourceURI)
    }

    func testReadsSourceFromWebArchiveMainResource() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard) { .alwaysAllow }
        let sourceURL = "https://example.com/report"
        let archive = try PropertyListSerialization.data(
            fromPropertyList: [
                "WebMainResource": ["WebResourceURL": sourceURL],
                "WebSubresources": [["WebResourceURL": "https://example.com/icon.png"]]
            ],
            format: .binary,
            options: 0
        )

        for type in ["com.apple.webarchive", "Apple Web Archive pasteboard type"] {
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString("Selected report text", forType: .string))
            XCTAssertTrue(pasteboard.setString("relative/path", forType: chromiumSourceType))
            XCTAssertTrue(pasteboard.setData(archive, forType: NSPasteboard.PasteboardType(type)))
            XCTAssertEqual(reader.read()?.sourceURI, sourceURL)
        }
    }

    func testMultipleTextItemsOnlyKeepASharedSourceURI() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard) { .alwaysAllow }
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository, clipboardReader: reader)
        let uri = "https://example.com/shared"
        let cases: [(addresses: [String?], expected: String?)] = [
            ([uri, uri], uri),
            ([nil, uri], nil),
            ([uri, nil], nil),
            ([uri, "https://example.com/different"], nil)
        ]

        let tasks = ["First task", "Second task"]
        for (addresses, expected) in cases {
            let items = zip(tasks, addresses).map { task, address in
                let item = NSPasteboardItem()
                XCTAssertTrue(item.setString(task, forType: .string))
                if let address { XCTAssertTrue(item.setString(address, forType: chromiumSourceType)) }
                return item
            }
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.writeObjects(items))
            await service.checkClipboardForTesting()
            await service.flushPendingSaves()

            let history = try await repository.loadAll()
            XCTAssertEqual(history.map(\.content), ["First task\nSecond task"])
            XCTAssertEqual(history.first?.metadata?.sourceURI, expected)
        }
    }

    func testUnmarkedWriteKeepsTextAndURIWhenTheSelectionDiffers() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
            self.safariSelection("Unattributed write\n")
        })
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        let uri = "https://example.com/document"

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Unattributed write", forType: .string))
        XCTAssertTrue(pasteboard.setString(uri, forType: chromiumSourceType))
        await service.checkClipboardForTesting()

        let history = await service.getHistory()
        let item = try XCTUnwrap(history.first)
        XCTAssertEqual(item.content, "Unattributed write")
        XCTAssertEqual(item.metadata?.sourceURI, uri)
        XCTAssertNil(item.sourceApp)
        XCTAssertNil(item.bundleIdentifier)
        XCTAssertNil(item.processID)
        XCTAssertNil(item.windowTitle)
    }

    func testMatchingSelectionRecordsAppAndWindowInHistory() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let text = "Safari からコピーした本文"
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
            self.safariSelection(text)
        })
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository, clipboardReader: reader)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))
        XCTAssertEqual(reader.read()?.text, text)
        XCTAssertNil(reader.read()?.source)
        await service.checkClipboardForTesting()
        await service.flushPendingSaves()

        let history = try await repository.loadAll()
        let item = try XCTUnwrap(history.first)
        XCTAssertEqual(item.content, text)
        XCTAssertEqual(item.sourceApp, "Safari")
        XCTAssertEqual(item.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(item.processID, 123)
        XCTAssertEqual(item.windowTitle, "Example Domain")
    }

    func testCopyDuringSelectionKeepsBothCopiesWithoutMixingSources() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("First", forType: .string))
        let firstCount = pasteboard.changeCount
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { count, _ in
            if count == firstCount {
                pasteboard.clearContents()
                XCTAssertTrue(pasteboard.setString("Second", forType: .string))
                return self.safariSelection("First")
            }
            return self.safariSelection("Second")
        })
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        await service.checkClipboardForTesting()
        await service.checkClipboardForTesting()

        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), ["Second", "First"])
        XCTAssertEqual(history.first?.windowTitle, "Example Domain")
        XCTAssertNil(history.last?.sourceApp)
        XCTAssertNil(history.last?.windowTitle)
    }

    func testAutomaticAndTransientWritesStayReadableAndOutOfHistory() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var selectionRevisions: [Int] = []
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { count, _ in
            selectionRevisions.append(count)
            return nil
        })
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository, clipboardReader: reader)
        let originalURI = "https://example.com/original"

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Original copy", forType: .string))
        XCTAssertTrue(pasteboard.setString(originalURI, forType: chromiumSourceType))
        let originalCount = pasteboard.changeCount
        await service.checkClipboardForTesting()

        for (type, content) in [
            ("org.nspasteboard.AutoGeneratedType", "Original copy"),
            ("org.nspasteboard.TransientType", "Temporary output")
        ] {
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString(content, forType: .string))
            XCTAssertTrue(pasteboard.setString("https://example.com/excluded", forType: chromiumSourceType))
            XCTAssertTrue(pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(type)))
            await service.checkClipboardForTesting()
            XCTAssertEqual(reader.read()?.text, content)
        }

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Next ordinary copy", forType: .string))
        await service.checkClipboardForTesting()
        await service.flushPendingSaves()

        let history = try await repository.loadAll()
        XCTAssertEqual(history.map(\.content), ["Next ordinary copy", "Original copy"])
        XCTAssertEqual(history.last?.metadata?.sourceURI, originalURI)
        XCTAssertEqual(selectionRevisions, [originalCount, pasteboard.changeCount])
    }

    func testDeclaredSourceIsRecordedAndAnEmptyDeclarationClearsIt() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
            XCTFail("A declared source must bypass selection inference")
            return self.safariSelection("Copied by a background app")
        })
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository, clipboardReader: reader)
        let declaredID = "com.apple.TextEdit"
        let text = "Copied by a background app"
        let uri = "https://example.com/document"

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))
        XCTAssertTrue(pasteboard.setString(declaredID, forType: sourceBundleType))
        XCTAssertTrue(pasteboard.setString(uri, forType: chromiumSourceType))
        await service.checkClipboardForTesting()
        await service.flushPendingSaves()
        let declaredHistory = try await repository.loadAll()
        let declared = try XCTUnwrap(declaredHistory.first)
        XCTAssertEqual(declared.bundleIdentifier, declaredID)
        XCTAssertNotNil(declared.sourceApp)
        XCTAssertNil(declared.processID)
        XCTAssertNil(declared.windowTitle)
        XCTAssertEqual(declared.metadata?.sourceURI, uri)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))
        XCTAssertTrue(pasteboard.setString("", forType: sourceBundleType))
        await service.checkClipboardForTesting()
        await service.flushPendingSaves()
        let unknownHistory = try await repository.loadAll()
        let unknown = try XCTUnwrap(unknownHistory.first)
        XCTAssertEqual(unknown.id, declared.id)
        XCTAssertNil(unknown.sourceApp)
        XCTAssertNil(unknown.bundleIdentifier)
        XCTAssertNil(unknown.processID)
        XCTAssertNil(unknown.windowTitle)
    }

    func testDifferentSourceDeclarationsAreOmitted() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
            XCTFail("Conflicting declarations must bypass selection inference")
            return self.safariSelection("First task\nSecond task")
        })
        let first = NSPasteboardItem()
        XCTAssertTrue(first.setString("First task", forType: .string))
        XCTAssertTrue(first.setString("com.apple.TextEdit", forType: sourceBundleType))
        let second = NSPasteboardItem()
        XCTAssertTrue(second.setString("Second task", forType: .string))
        XCTAssertTrue(second.setString("com.apple.finder", forType: sourceBundleType))

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([first, second]))
        let snapshot = await reader.readForHistory(changeCount: pasteboard.changeCount)
        let captured = try XCTUnwrap(snapshot)
        XCTAssertEqual(captured.text, "First task\nSecond task")
        XCTAssertNil(captured.source)
    }

    private func safariSelection(_ text: String) -> ClipboardReader.Selection {
        ClipboardReader.Selection(
            text: text,
            source: .init(name: "Safari", bundleID: "com.apple.Safari", processID: 123, windowTitle: "Example Domain"),
            webPageURL: nil
        )
    }
}

extension ClipboardReaderTests {
    func testChromeFormattedMultilineSelectionRecordsAppAndWindowInHistory() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let text = "Kipple 右クリック調査 6D381\n\nChrome コピーの選択テキスト\n段落内の改行を含む\n\n最初の項目\n次の項目"
        let selection = "Kipple 右クリック調査 6D381Chrome\u{00A0}コピーの選択テキスト\n段落内の改行を含む• 最初の項目• 次の項目"
        let page = try XCTUnwrap(URL(string: "https://example.com/document"))
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
            self.chromeSelection(selection, page: page)
        })
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository, clipboardReader: reader)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))
        XCTAssertTrue(pasteboard.setString(page.absoluteString, forType: chromiumSourceType))
        await service.checkClipboardForTesting()
        await service.flushPendingSaves()

        let history = try await repository.loadAll()
        let item = try XCTUnwrap(history.first)
        XCTAssertEqual(item.content, text)
        XCTAssertEqual(item.metadata?.sourceURI, page.absoluteString)
        XCTAssertEqual(item.sourceApp, "Google Chrome")
        XCTAssertEqual(item.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(item.windowTitle, "Example Domain - Google Chrome")
    }

    func testChromeMultilineMatchingRejectsDifferencesInWordsNumbersAndPunctuation() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let page = try XCTUnwrap(URL(string: "https://example.com/document"))
        let cases = [
            ("Task A\nItem 120", "Task B• Item 120"),
            ("Task A\nItem 120", "TaskA• Item 120"),
            ("Task A\nItem 120", "Task A• Item 121"),
            ("Task A\nItem 120", "Task A• Item 12 0"),
            ("Task A\n12\n3", "Task A123"),
            ("Task A\nItem 120", "Task A• Item 120 extra"),
            ("Task A\nItem 120", "Task A1. Item 120"),
            ("Task A\nItem 120", "Task A- Item 120"),
            ("Task A\nItem • 120", "Task A• Item 120"),
            ("Task A", "Task\u{00A0}A")
        ]
        for (copied, selection) in cases {
            let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
                self.chromeSelection(selection, page: page)
            })
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString(copied, forType: .string))
            XCTAssertTrue(pasteboard.setString(page.absoluteString, forType: chromiumSourceType))

            let snapshot = await reader.readForHistory(changeCount: pasteboard.changeCount)

            XCTAssertEqual(snapshot?.text, copied)
            XCTAssertNil(snapshot?.source, "Copied: \(copied.debugDescription), selected: \(selection.debugDescription)")
        }
    }

    func testChromeMultilineMatchingRequiresChromiumMetadataAndTheSameFocusedWebPage() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let page = try XCTUnwrap(URL(string: "https://example.com/document"))
        let otherPage = try XCTUnwrap(URL(string: "https://example.com/other"))
        let copied = "Task A\nItem 120"
        let selected = "Task A• Item 120"
        let cases: [(clipboardPage: URL?, selection: ClipboardReader.Selection)] = [
            (nil, chromeSelection(selected, page: page)),
            (page, chromeSelection(selected, page: nil)),
            (page, chromeSelection(selected, page: otherPage)),
            (page, .init(text: selected, source: safariSelection(selected).source, webPageURL: page))
        ]
        for (clipboardPage, selection) in cases {
            let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
                selection
            })
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString(copied, forType: .string))
            if let clipboardPage {
                XCTAssertTrue(pasteboard.setString(clipboardPage.absoluteString, forType: chromiumSourceType))
            }

            let snapshot = await reader.readForHistory(changeCount: pasteboard.changeCount)

            XCTAssertEqual(snapshot?.text, copied)
            XCTAssertNil(snapshot?.source)
        }
    }

    private func chromeSelection(_ text: String, page: URL?) -> ClipboardReader.Selection {
        ClipboardReader.Selection(
            text: text,
            source: .init(
                name: "Google Chrome", bundleID: "com.google.Chrome", processID: 456,
                windowTitle: "Example Domain - Google Chrome"
            ),
            webPageURL: page
        )
    }
}
