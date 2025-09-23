import XCTest
@testable import Kipple

extension ModernClipboardService {
    func resetForTesting() async {
        await stopMonitoring()
        await clearHistory(keepPinned: false)
        await clearAllHistory()
        await setMaxHistoryItems(300)
        await MainActor.run {
            AppSettings.shared.maxHistoryItems = 300
            AppSettings.shared.maxPinnedItems = 20
        }
    }

    func useTestingRepository(_ repository: any ClipboardRepositoryProtocol) async {
        await MainActor.run {
            RepositoryProvider.useTestingRepository(repository)
        }
        await setRepository(repository)
        await loadHistoryFromRepository()
    }
}
