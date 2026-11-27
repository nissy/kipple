import Foundation
import SwiftData
import XCTest
@testable import Kipple

@MainActor
final class RichTextMigrationTests: XCTestCase {
    func testExistingHistoryMigratesWithoutLosingContentOrMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store")
        let original = ClipItem(
            content: "Existing history", sourceApp: "Safari",
            metadata: ClipMetadata(title: "Existing title", source: .clipboard)
        )
        try autoreleasepool {
            let schema = Schema([LegacyClipboardSchema.ClipItemModel.self, MCPReceiptModel.self])
            let configuration = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(LegacyClipboardSchema.ClipItemModel(from: original, isPinned: true))
            try context.save()
        }
        let schema = Schema([ClipItemModel.self, MCPReceiptModel.self])
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let repository = try SwiftDataRepository.make(container: container)
        let items = try await repository.loadAll()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first, original)
        XCTAssertNil(items.first?.richText)

        let missingPreviews = try await repository.loadStartupPreviews(limit: 50)
        XCTAssertTrue(missingPreviews.isEmpty)
        try await repository.backfillHistoryPreviews()
        try await repository.backfillHistoryPreviews()
        let previews = try await repository.loadStartupPreviews(limit: 50)
        XCTAssertEqual(previews.map(\.id), [original.id])
        XCTAssertEqual(previews.first?.title, original.title)
        XCTAssertEqual(previews.first?.text, original.content)
        let fullItem = try await repository.load(ids: [original.id])
        XCTAssertEqual(fullItem, [original])
    }
}
