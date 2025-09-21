import Foundation
import SwiftUI

@MainActor
protocol MainViewModelProtocol: AnyObject {
    var filteredHistory: [ClipItem] { get set }
    var pinnedHistory: [ClipItem] { get set }
    var searchText: String { get set }
    var editorText: String { get set }
    var showOnlyURLs: Bool { get set }

    func loadHistory()
    func copyToClipboard(_ item: ClipItem)
    func copyEditor()
    func clearEditor()
    func togglePin(for item: ClipItem) async
    func deleteItem(_ item: ClipItem) async
    func clearHistory(keepPinned: Bool) async
}
