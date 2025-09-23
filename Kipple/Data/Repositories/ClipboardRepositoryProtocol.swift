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
    func loadAll() async throws -> [ClipItem]
    func delete(_ item: ClipItem) async throws
    func clear() async throws
    func clear(keepPinned: Bool) async throws
    func applyChanges(inserted: [ClipItem], updated: [ClipItem], removed: [UUID]) async throws
}
