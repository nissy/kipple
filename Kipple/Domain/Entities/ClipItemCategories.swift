import Foundation

enum BuiltInCategory {
    static let none = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let url = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let ocr = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let ai = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let automatic: Set<UUID> = [url, ocr, ai]
}

struct CategoryOverrides: Codable, Equatable, Sendable {
    var added: Set<UUID> = []
    var removed: Set<UUID> = []
}

extension ClipItem {
    var automaticCategoryIDs: Set<UUID> {
        var result = Set<UUID>()
        if category == .url { result.insert(BuiltInCategory.url) }
        if metadata?.sources.contains(.ocr) == true { result.insert(BuiltInCategory.ocr) }
        if metadata?.sources.contains(.mcp) == true { result.insert(BuiltInCategory.ai) }
        return result
    }

    // Keep the legacy scalar readable; edits are stored in the existing metadata blob.
    private var categoryOverrides: CategoryOverrides {
        if let overrides = metadata?.categoryOverrides { return overrides }
        guard let userCategoryId else { return CategoryOverrides() }
        if userCategoryId == BuiltInCategory.none {
            return CategoryOverrides(removed: BuiltInCategory.automatic)
        }
        return CategoryOverrides(added: [userCategoryId])
    }

    var categoryIDs: Set<UUID> {
        let overrides = categoryOverrides
        return automaticCategoryIDs.union(overrides.added).subtracting(overrides.removed)
    }

    mutating func setCategory(_ id: UUID, enabled: Bool) {
        guard id != BuiltInCategory.none else { return }
        var overrides = categoryOverrides
        if enabled {
            overrides.added.insert(id)
            overrides.removed.remove(id)
        } else {
            overrides.added.remove(id)
            overrides.removed.insert(id)
        }
        var details = metadata ?? ClipMetadata()
        details.categoryOverrides = overrides
        metadata = details
    }

    mutating func removeCategoryDefinition(_ id: UUID) {
        var overrides = categoryOverrides
        overrides.added.remove(id)
        overrides.removed.remove(id)
        var details = metadata ?? ClipMetadata()
        details.categoryOverrides = overrides
        metadata = details
        if userCategoryId == id { userCategoryId = nil }
    }
}

struct CategoryFilter: Equatable {
    enum Match: String, CaseIterable { case all, any }
    var ids: Set<UUID> = []
    var match: Match = .all

    mutating func toggle(_ id: UUID) {
        if ids.remove(id) != nil { return }
        if id == BuiltInCategory.none { ids = [id] } else {
            ids.remove(BuiltInCategory.none)
            ids.insert(id)
        }
    }

    func includes(_ item: ClipItem) -> Bool {
        guard !ids.isEmpty else { return true }
        let categories = item.categoryIDs
        if ids.contains(BuiltInCategory.none) { return categories.isEmpty }
        return match == .all ? ids.isSubset(of: categories) : !ids.isDisjoint(with: categories)
    }
}
