import Foundation

// MARK: - Modern Clipboard Service Protocol

protocol ModernClipboardServiceProtocol {
    // Core functionality
    func getHistory() async -> [ClipItem]
    func startMonitoring() async
    func stopMonitoring() async
    func isMonitoring() async -> Bool
    func copyToClipboard(_ content: String, fromEditor: Bool) async
    func recopyFromHistory(_ item: ClipItem) async
    func clearSystemClipboard() async

    // History management
    func clearAllHistory() async
    func clearHistory(keepPinned: Bool) async
    func togglePin(for item: ClipItem) async -> Bool
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
