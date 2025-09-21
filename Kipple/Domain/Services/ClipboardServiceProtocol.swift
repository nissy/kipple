//
//  ClipboardServiceProtocol.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import Foundation

protocol ClipboardServiceProtocol: AnyObject {
    var history: [ClipItem] { get }
    var pinnedItems: [ClipItem] { get }
    var currentClipboardContent: String? { get }
    var onHistoryChanged: ((ClipItem) -> Void)? { get set }

    func startMonitoring()
    func stopMonitoring()
    func copyToClipboard(_ content: String, fromEditor: Bool)
    func clearAllHistory()
    func clearHistory(keepPinned: Bool) async
    func togglePin(for item: ClipItem) -> Bool
    func deleteItem(_ item: ClipItem)
    func deleteItem(_ item: ClipItem) async
    func flushPendingSaves() async
}
