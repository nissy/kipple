import Foundation

struct MCPHistoryMutation {
    let registered: [ClipItem]
    let candidate: [ClipItem]

    init(
        items: [ClipItem], history: [ClipItem], capacity: Int,
        isProtected: (ClipItem) -> Bool = { $0.hasCustomCategory }
    ) throws {
        guard (1...50).contains(items.count) else { throw MCPFailure.invalidInput }
        var registered: [ClipItem] = []
        var byContent: [String: ClipItem] = [:]
        for var item in items {
            if let previous = history.first(where: { $0.content == item.content }) {
                item.id = previous.id
                item.userCategoryId = previous.userCategoryId
                item.metadata = (item.metadata ?? ClipMetadata()).inheritingDetails(from: previous.metadata)
            }
            if let duplicate = byContent[item.content] {
                guard duplicate.metadata == item.metadata else { throw MCPFailure.invalidInput }
                item = duplicate
            } else {
                byContent[item.content] = item
            }
            registered.append(item)
        }
        var seen = Set<UUID>()
        let unique = registered.filter { seen.insert($0.id).inserted }
        let remaining = history.filter { !seen.contains($0.id) }
        let registeredInLimit = unique.filter { !isProtected($0) }.count
        var available = capacity - registeredInLimit
        guard available >= 0 else { throw MCPFailure.capacity }
        let candidate = unique + remaining.filter { item in
            if isProtected(item) { return true }
            guard available > 0 else { return false }
            available -= 1
            return true
        }
        self.registered = registered
        self.candidate = candidate
    }
}
