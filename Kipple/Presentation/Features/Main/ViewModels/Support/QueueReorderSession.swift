import Foundation

struct QueueReorderSession: Equatable {
    let itemID: UUID
    let queue: [UUID]
    let epoch: UInt64
    let copyEpoch: UInt64?
    let pasteboardChangeCount: Int
    let mode: MainViewModel.PasteMode
    let searchText: String
    let categoryFilter: CategoryFilter
    let filterFlags: [Bool]
    let filteredIDs: [UUID]
}

struct QueueReorderTarget: Equatable {
    let itemID: UUID?
    let insertAfter: Bool

    static let end = QueueReorderTarget(itemID: nil, insertAfter: true)

    func applying(to session: QueueReorderSession) -> [UUID]? {
        var result = session.queue.filter { $0 != session.itemID }
        guard let itemID else {
            result.append(session.itemID)
            return result
        }
        guard session.queue.contains(itemID) else { return nil }
        guard itemID != session.itemID else { return session.queue }
        guard let index = result.firstIndex(of: itemID) else { return nil }
        result.insert(session.itemID, at: index + (insertAfter ? 1 : 0))
        return result
    }
}

@MainActor
struct QueueReorderActions {
    let begin: (UUID) -> QueueReorderSession?
    let isValid: (QueueReorderSession) -> Bool
    let commit: (QueueReorderSession, QueueReorderTarget) -> Void

    func startQueue(itemID: UUID) {
        guard let session = begin(itemID), session.mode == .clipboard else { return }
        commit(session, .end)
    }
}
