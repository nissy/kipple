import Foundation
import SwiftData

@Model
final class ClipItemModel {
    @Attribute(.unique) var id: UUID
    var content: String
    var timestamp: Date
    var kindRawValue: String
    var appName: String?
    var windowTitle: String?
    var bundleId: String?
    var processId: Int32?
    var isFromEditor: Bool
    var userCategoryId: UUID?
    var metadataData: Data?
    @Attribute(.externalStorage) var richTextData: Data?

    init(
        id: UUID = UUID(),
        content: String,
        timestamp: Date = Date(),
        kind: ClipItemKind = .text,
        appName: String? = nil,
        windowTitle: String? = nil,
        bundleId: String? = nil,
        processId: Int32? = nil,
        isFromEditor: Bool = false,
        userCategoryId: UUID? = nil,
        metadata: ClipMetadata? = nil,
        richText: ClipboardRichText? = nil
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.kindRawValue = kind.rawValue
        self.appName = appName
        self.windowTitle = windowTitle
        self.bundleId = bundleId
        self.processId = processId
        self.isFromEditor = isFromEditor
        self.userCategoryId = userCategoryId
        self.metadataData = metadata.flatMap { try? JSONEncoder().encode($0) }
        self.richTextData = richText.flatMap { try? JSONEncoder().encode($0) }
    }

    convenience init(from clipItem: ClipItem) {
        self.init(
            id: clipItem.id,
            content: clipItem.content,
            timestamp: clipItem.timestamp,
            kind: clipItem.kind,
            appName: clipItem.sourceApp,
            windowTitle: clipItem.windowTitle,
            bundleId: clipItem.bundleIdentifier,
            processId: clipItem.processID,
            isFromEditor: clipItem.isFromEditor ?? false,
            userCategoryId: clipItem.userCategoryId,
            metadata: clipItem.metadata,
            richText: clipItem.richText
        )
    }

    func toClipItem() -> ClipItem {
        toClipItem(metadata: decodedMetadata)
    }

    var hasCustomCategory: Bool {
        CategoryOverrides.resolve(decodedMetadata?.categoryOverrides, legacyID: userCategoryId).hasCustomCategory
    }

    func toCustomCategorizedClipItem() -> ClipItem? {
        let metadata = decodedMetadata
        let overrides = CategoryOverrides.resolve(metadata?.categoryOverrides, legacyID: userCategoryId)
        guard overrides.hasCustomCategory else { return nil }
        return toClipItem(metadata: metadata)
    }

    private var decodedMetadata: ClipMetadata? {
        metadataData.flatMap { try? JSONDecoder().decode(ClipMetadata.self, from: $0) }
    }

    private func toClipItem(metadata: ClipMetadata?) -> ClipItem {
        ClipItem(
            id: id,
            content: content,
            timestamp: timestamp,
            kind: ClipItemKind(rawValue: kindRawValue) ?? .text,
            sourceApp: appName,
            windowTitle: windowTitle,
            bundleIdentifier: bundleId,
            processID: processId,
            isFromEditor: isFromEditor,
            userCategoryId: userCategoryId,
            metadata: metadata,
            richText: richTextData.flatMap { try? JSONDecoder().decode(ClipboardRichText.self, from: $0) }
        )
    }

    func toDomainModel() -> ClipItem {
        return toClipItem()
    }
}

// MARK: - Batch Operations Helper

extension ModelContext {
    func batchDelete<T: PersistentModel>(
        _ type: T.Type,
        predicate: Predicate<T>? = nil
    ) throws {
        let fetchDescriptor = FetchDescriptor<T>(predicate: predicate)
        let items = try fetch(fetchDescriptor)
        for item in items {
            delete(item)
        }
        try save()
    }

    func batchInsert<T: PersistentModel>(_ items: [T]) throws {
        for item in items {
            insert(item)
        }
        try save()
    }
}
