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
            content: "Existing pinned history", isPinned: true, sourceApp: "Safari",
            metadata: ClipMetadata(title: "Existing title", source: .clipboard)
        )
        try autoreleasepool {
            let schema = Schema([LegacyClipboardSchema.ClipItemModel.self, MCPReceiptModel.self])
            let configuration = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(LegacyClipboardSchema.ClipItemModel(from: original))
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
    }
}
