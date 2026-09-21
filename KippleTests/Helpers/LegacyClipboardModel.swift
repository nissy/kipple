import Foundation
import SwiftData
@testable import Kipple

// Snapshot of the schema before rich-text history, used to verify migration.
enum LegacyClipboardSchema {
    @Model
    final class ClipItemModel {
        @Attribute(.unique) var id: UUID
        var content: String
        var timestamp: Date
        var isPinned: Bool
        var kindRawValue: String
        var appName: String?
        var windowTitle: String?
        var bundleId: String?
        var processId: Int32?
        var isFromEditor: Bool
        var userCategoryId: UUID?
        var metadataData: Data?
    
        init(
            id: UUID = UUID(),
            content: String,
            timestamp: Date = Date(),
            isPinned: Bool = false,
            kind: ClipItemKind = .text,
            appName: String? = nil,
            windowTitle: String? = nil,
            bundleId: String? = nil,
            processId: Int32? = nil,
            isFromEditor: Bool = false,
            userCategoryId: UUID? = nil,
            metadata: ClipMetadata? = nil
        ) {
            self.id = id
            self.content = content
            self.timestamp = timestamp
            self.isPinned = isPinned
            self.kindRawValue = kind.rawValue
            self.appName = appName
            self.windowTitle = windowTitle
            self.bundleId = bundleId
            self.processId = processId
            self.isFromEditor = isFromEditor
            self.userCategoryId = userCategoryId
            self.metadataData = metadata.flatMap { try? JSONEncoder().encode($0) }
        }
    
        convenience init(from clipItem: ClipItem) {
            self.init(
                id: clipItem.id,
                content: clipItem.content,
                timestamp: clipItem.timestamp,
                isPinned: clipItem.isPinned,
                kind: clipItem.kind,
                appName: clipItem.sourceApp,
                windowTitle: clipItem.windowTitle,
                bundleId: clipItem.bundleIdentifier,
                processId: clipItem.processID,
                isFromEditor: clipItem.isFromEditor ?? false,
                userCategoryId: clipItem.userCategoryId,
                metadata: clipItem.metadata
            )
        }
    
        func toClipItem() -> ClipItem {
            return ClipItem(
                id: id,
                content: content,
                timestamp: timestamp,
                isPinned: isPinned,
                kind: ClipItemKind(rawValue: kindRawValue) ?? .text,
                sourceApp: appName,
                windowTitle: windowTitle,
                bundleIdentifier: bundleId,
                processID: processId,
                isFromEditor: isFromEditor,
                userCategoryId: userCategoryId,
                metadata: metadataData.flatMap { try? JSONDecoder().decode(ClipMetadata.self, from: $0) }
            )
        }
    
        func toDomainModel() -> ClipItem {
            return toClipItem()
        }
    }
}
