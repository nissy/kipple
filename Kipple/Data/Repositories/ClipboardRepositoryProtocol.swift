//
//  ClipboardRepositoryProtocol.swift
//  Kipple
//
//  Created by Kipple on 2025/07/11.
//

import Foundation

protocol ClipboardRepositoryProtocol: Sendable {
    func save(_ items: [ClipItem]) async throws
    func replaceAll(with items: [ClipItem]) async throws
    func load(limit: Int) async throws -> [ClipItem]
    func load(ids: Set<UUID>) async throws -> [ClipItem]
    func loadAll() async throws -> [ClipItem]
    func loadItemIDs() async throws -> Set<UUID>
    func loadCategorized() async throws -> [ClipItem]
    func loadStartupPreviews(limit: Int) async throws -> [HistoryRowPreview]
    func loadFullStartupItem(id: UUID) async throws -> ClipItem?
    func backfillHistoryPreviews() async throws
    func delete(_ item: ClipItem) async throws
    func clear() async throws
    func applyChanges(inserted: [ClipItem], updated: [ClipItem], removed: [UUID]) async throws
}

extension ClipboardRepositoryProtocol {
    func loadStartupPreviews(limit: Int) async throws -> [HistoryRowPreview] { [] }

    func loadFullStartupItem(id: UUID) async throws -> ClipItem? { try await load(ids: [id]).first }

    func backfillHistoryPreviews() async throws {}

    func load(ids: Set<UUID>) async throws -> [ClipItem] {
        guard !ids.isEmpty else { return [] }
        return try await loadAll().filter { ids.contains($0.id) }
    }

    func loadItemIDs() async throws -> Set<UUID> {
        Set(try await loadAll().map(\.id))
    }

    func loadCategorized() async throws -> [ClipItem] {
        try await loadAll().filter(\.hasCustomCategory)
    }
}
