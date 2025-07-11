//
//  ClipboardRepositoryProtocol.swift
//  Kipple
//
//  Created by Kipple on 2025/07/11.
//

import Foundation

protocol ClipboardRepositoryProtocol {
    func save(_ items: [ClipItem]) async throws
    func load(limit: Int) async throws -> [ClipItem]
    func loadAll() async throws -> [ClipItem]
    func delete(_ item: ClipItem) async throws
    func clear(keepPinned: Bool) async throws
}
