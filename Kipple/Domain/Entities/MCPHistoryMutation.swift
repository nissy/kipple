import Foundation

struct MCPHistoryMutation {
    let registered: [ClipItem]
    let candidate: [ClipItem]

    init(items: [ClipItem], history: [ClipItem], capacity: Int) throws {
        guard (1...50).contains(items.count) else { throw MCPFailure.invalidInput }
        var registered: [ClipItem] = []
        var byContent: [String: ClipItem] = [:]
        for var item in items {
            if let previous = history.first(where: { $0.content == item.content }) {
                item.id = previous.id
                item.isPinned = previous.isPinned
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
        let pinned = remaining.filter(\.isPinned)
        guard unique.count + pinned.count <= capacity else { throw MCPFailure.capacity }
        let available = capacity - unique.count - pinned.count
        let retainedUnpinned = Set(remaining.filter { !$0.isPinned }.prefix(available).map(\.id))
        let candidate = unique + remaining.filter { $0.isPinned || retainedUnpinned.contains($0.id) }
        guard candidate.reduce(0, { $0 + $1.content.utf8.count }) <= 64 * 1024 * 1024 else {
            throw MCPFailure.capacity
        }
        self.registered = registered
        self.candidate = candidate
    }
}
