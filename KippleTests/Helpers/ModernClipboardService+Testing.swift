import XCTest
@testable import Kipple

extension ModernClipboardService {
    func resetForTesting() async {
        await stopMonitoring()
        await clearHistory(keepPinned: false)
        await clearAllHistory()
        await clearRepositoryForTesting()
        await setMaxHistoryItems(300)
        await resetAutoPinSequenceForTesting()
        await MainActor.run {
            AppSettings.shared.maxHistoryItems = 300
            AppSettings.shared.maxPinnedItems = 20
            AppSettings.shared.autoPinRepeatedCopyEnabled = true
            AppSettings.shared.autoPinRepeatedCopyIntervalSeconds = 5
            AppSettings.shared.autoPinRepeatedCopyCount = 3
        }

        await ModernClipboardServiceAdapter.shared.resetAdapterStateForTesting()
    }

    func useTestingRepository(_ repository: any ClipboardRepositoryProtocol) async {
        await MainActor.run {
            RepositoryProvider.useTestingRepository(repository)
        }
        await setRepository(repository)
        await loadHistoryFromRepository()
    }
}
