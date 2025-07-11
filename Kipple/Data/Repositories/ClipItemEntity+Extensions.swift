//
//  ClipItemEntity+Extensions.swift
//  Kipple
//
//  Created by Kipple on 2025/07/11.
//

import Foundation
import CoreData

extension ClipItemEntity {
    func toClipItem() -> ClipItem {
        ClipItem(
            id: id ?? UUID(),
            content: content ?? "",
            timestamp: timestamp ?? Date(),
            isPinned: isPinned,
            kind: ClipItemKind(rawValue: kind ?? "") ?? .text,
            sourceApp: sourceApp,
            windowTitle: windowTitle,
            bundleIdentifier: bundleIdentifier,
            processID: processID == 0 ? nil : processID,
            isFromEditor: isFromEditor
        )
    }
    
    func update(from clipItem: ClipItem) {
        self.id = clipItem.id
        self.content = clipItem.content
        self.timestamp = clipItem.timestamp
        self.isPinned = clipItem.isPinned
        self.kind = clipItem.kind.rawValue
        self.sourceApp = clipItem.sourceApp
        self.windowTitle = clipItem.windowTitle
        self.bundleIdentifier = clipItem.bundleIdentifier
        self.processID = clipItem.processID ?? 0
        self.isFromEditor = clipItem.isFromEditor ?? false
    }
    
    static func create(from clipItem: ClipItem, in context: NSManagedObjectContext) -> ClipItemEntity {
        let entity = ClipItemEntity(context: context)
        entity.update(from: clipItem)
        return entity
    }
}
