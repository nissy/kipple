import Foundation

// MARK: - Modern Clipboard Service Protocol

protocol ModernClipboardServiceProtocol {
    // Core functionality
    func getHistory() async -> [ClipItem]
    func startMonitoring() async
    func stopMonitoring() async
    func isMonitoring() async -> Bool
    func copyToClipboard(_ content: String, fromEditor: Bool) async
    func writeToClipboardOnly(_ content: String) async
    func addEditorItems(_ contents: [String]) async -> [ClipItem]
    func recopyFromHistory(_ item: ClipItem) async
    func clearSystemClipboard() async

    // History management
    @discardableResult
    func clearHistory(keepingCategories: Bool) async -> Result<Int, Error>
    func deleteItem(_ item: ClipItem) async
    func updateItem(_ item: ClipItem) async

    // Search and filter
    func searchHistory(query: String) async -> [ClipItem]

    // Status and configuration
    func getCurrentClipboardContent() async -> String?
    func getCurrentInterval() async -> TimeInterval
    func setMaxHistoryItems(_ max: Int) async

    // Persistence
    func flushPendingSaves() async
}
