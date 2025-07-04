//
//  ClipItem.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Foundation

enum ClipItemKind: String, Codable {
    case text
    case image
    case file
    case url
}

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let timestamp: Date
    var isPinned: Bool
    let kind: ClipItemKind
    let sourceApp: String?
    
    // Computed properties
    var fullContent: String {
        content
    }
    
    var displayContent: String {
        let maxLength = 50
        guard content.count > maxLength else {
            return content
        }
        // prefix は効率的なので問題ないが、早期リターンで無駄な処理を削減
        return String(content.prefix(maxLength)) + "..."
    }
    
    var characterCount: Int {
        content.count
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    init(content: String, isPinned: Bool = false, kind: ClipItemKind = .text, sourceApp: String? = nil) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.isPinned = isPinned
        self.kind = kind
        self.sourceApp = sourceApp
    }
    
    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id
    }
}
