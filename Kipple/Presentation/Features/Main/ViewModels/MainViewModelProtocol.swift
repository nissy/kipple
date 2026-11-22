import Foundation
import SwiftUI

@MainActor
protocol MainViewModelProtocol: AnyObject {
    var filteredHistory: [ClipItem] { get set }
    var searchText: String { get set }
    var editorText: String { get set }
    var showOnlyURLs: Bool { get set }

    func loadHistory()
    func copyToClipboard(_ item: ClipItem)
    func copyEditor()
    func clearEditor()
    func deleteItem(_ item: ClipItem) async
    @discardableResult
    func clearHistory(keepingCategories: Bool) async -> Result<Int, Error>
}
