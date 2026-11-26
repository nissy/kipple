import AppKit
import Combine
import XCTest
@testable import Kipple

@MainActor
final class DesktopNoteRepeatedCopyTests: XCTestCase {
    func testThirdExternalCopyPostsOneNoteForTheExistingHistoryItem() async throws {
        let settings = AppSettings.shared
        let previous = settings.desktopNoteOnRepeatedCopy
        let previousDisplay = settings.desktopNoteDisplayID
        let selected = try XCTUnwrap(DesktopNoteDisplay.connected.last)
        settings.desktopNoteOnRepeatedCopy = true
        settings.desktopNoteDisplayID = selected.id
        defer {
            settings.desktopNoteOnRepeatedCopy = previous
            settings.desktopNoteDisplayID = previousDisplay
        }
        var soundCount = 0
        let playSound: () -> Void = { soundCount += 1 }
        let fixture = try RepeatedCopyFixture(playRepeatedCopySound: playSound)
        defer { fixture.pasteboard.releaseGlobally() }
        let text = "Review the desktop release checklist"

        let first = await fixture.copy(text)
        let original = try XCTUnwrap(first)
        _ = await fixture.copy(text)
        await fixture.service.checkClipboardForTesting()
        await fixture.service.recopyFromHistory(original)
        await fixture.service.checkClipboardForTesting()
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertEqual(soundCount, 0)

        let third = await fixture.copy(text)
        XCTAssertEqual(third?.id, original.id)
        for _ in 0..<50 where !fixture.coordinator.isPosted(original.id) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(fixture.coordinator.isPosted(original.id))
        XCTAssertEqual(soundCount, 1)
        let window = try XCTUnwrap(fixture.noteWindow(for: original.id))
        defer { window.close() }
        XCTAssertTrue(selected.screen.visibleFrame.contains(window.frame))

        for _ in 0..<3 { _ = await fixture.copy(text) }
        for _ in 0..<50 where fixture.requests.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(fixture.requests, [original.id, original.id])
        await Task.yield()
        XCTAssertIdentical(fixture.noteWindow(for: original.id), window)
        XCTAssertTrue(fixture.coordinator.isPosted(original.id))
        XCTAssertEqual(soundCount, 1)
        let history = await fixture.service.getHistory()
        XCTAssertEqual(history.map(\.id), [original.id])
    }

    func testManuallyPostingNoteDoesNotPlayRepeatedCopySound() async throws {
        var soundCount = 0
        let playSound: () -> Void = { soundCount += 1 }
        let fixture = try RepeatedCopyFixture(playRepeatedCopySound: playSound)
        defer { fixture.pasteboard.releaseGlobally() }
        let item = await fixture.copy("Add a note from history")
        let itemID = try XCTUnwrap(item?.id)

        await fixture.coordinator.toggle(itemID, on: nil)
        defer { fixture.noteWindow(for: itemID)?.close() }

        XCTAssertTrue(fixture.coordinator.isPosted(itemID))
        XCTAssertEqual(soundCount, 0)
    }

    func testRepeatedCopiesStartOverAfterATimeoutOrDifferentText() async throws {
        let settings = AppSettings.shared
        let previous = settings.desktopNoteOnRepeatedCopy
        settings.desktopNoteOnRepeatedCopy = true
        defer { settings.desktopNoteOnRepeatedCopy = previous }
        let fixture = try RepeatedCopyFixture()
        defer { fixture.pasteboard.releaseGlobally() }
        let text = "Follow up on the action item"

        _ = await fixture.copy(text)
        _ = await fixture.copy(text)
        try await Task.sleep(for: .milliseconds(5_100))
        _ = await fixture.copy(text)
        XCTAssertTrue(fixture.requests.isEmpty)
        _ = await fixture.copy("Another action item")
        _ = await fixture.copy(text)
        _ = await fixture.copy(text)
        XCTAssertTrue(fixture.requests.isEmpty)
        let third = await fixture.copy(text)
        let itemID = try XCTUnwrap(third?.id)
        for _ in 0..<50 where !fixture.coordinator.isPosted(itemID) {
            try await Task.sleep(for: .milliseconds(10))
        }
        defer { fixture.noteWindow(for: itemID)?.close() }
        XCTAssertEqual(fixture.requests, [itemID])
        XCTAssertTrue(fixture.coordinator.isPosted(itemID))
    }

    func testRepeatedCopySettingCanBeTurnedOffAndBackOn() async throws {
        let settings = AppSettings.shared
        let previous = settings.desktopNoteOnRepeatedCopy
        settings.desktopNoteOnRepeatedCopy = false
        defer { settings.desktopNoteOnRepeatedCopy = previous }
        let fixture = try RepeatedCopyFixture()
        defer { fixture.pasteboard.releaseGlobally() }
        let text = "Schedule a follow-up"

        for _ in 0..<3 { _ = await fixture.copy(text) }
        XCTAssertTrue(fixture.requests.isEmpty)

        settings.desktopNoteOnRepeatedCopy = true
        _ = await fixture.copy(text)
        _ = await fixture.copy(text)
        settings.desktopNoteOnRepeatedCopy = false
        settings.desktopNoteOnRepeatedCopy = true
        _ = await fixture.copy(text)
        _ = await fixture.copy(text)
        XCTAssertTrue(fixture.requests.isEmpty)

        let third = await fixture.copy(text)
        let itemID = try XCTUnwrap(third?.id)
        for _ in 0..<50 where !fixture.coordinator.isPosted(itemID) {
            try await Task.sleep(for: .milliseconds(10))
        }
        defer { fixture.noteWindow(for: itemID)?.close() }
        XCTAssertEqual(fixture.requests, [itemID])
        XCTAssertTrue(fixture.coordinator.isPosted(itemID))
    }

    @MainActor
    private final class RepeatedCopyFixture {
        let pasteboard = NSPasteboard.withUniqueName()
        let service: ModernClipboardService
        let coordinator: DesktopNoteWindowCoordinator
        private(set) var requests: [UUID] = []
        private var observation: AnyCancellable?

        init(playRepeatedCopySound: @escaping () -> Void = {}) throws {
            let pasteboard = self.pasteboard
            service = ModernClipboardService(
                testRepository: try SwiftDataRepository.make(inMemory: true),
                clipboardWriter: { item in
                    pasteboard.clearContents()
                    return pasteboard.setString(item.content, forType: .string) ? pasteboard.changeCount : -1
                },
                clipboardReader: ClipboardReader(
                    pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in nil }
                )
            )
            let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
            coordinator = DesktopNoteWindowCoordinator(adapter: adapter, playRepeatedCopySound: playRepeatedCopySound)
            observation = adapter.repeatedCopyDesktopNoteRequests.sink { [weak self] in self?.requests.append($0) }
        }

        func copy(_ content: String) async -> ClipItem? {
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString(content, forType: .string))
            await service.checkClipboardForTesting()
            return await service.getHistory().first
        }

        func noteWindow(for itemID: UUID) -> DesktopNotePanel? {
            NSApp.windows.compactMap { $0 as? DesktopNotePanel }.first {
                ($0.contentViewController as? DesktopNoteContentController)?.hostingController.rootView.item.id == itemID
            }
        }
    }
}
