import XCTest
@testable import Kipple

extension ModernClipboardService {
    func resetForTesting() async {
        await useCategoryStoreFixture()
        await stopMonitoring()
        await clearHistory(keepingCategories: false)
        await clearRepositoryForTesting()
        await setMaxHistoryItems(300)
        await MainActor.run {
            AppSettings.shared.maxHistoryItems = 300
        }

        await ModernClipboardServiceAdapter.shared.resetAdapterStateForTesting()
    }

    func useCategoryStoreFixture() async {
        await setCategoryStoreForTesting(TestCategoryStore.shared)
    }

    func useTestingRepository(_ repository: any ClipboardRepositoryProtocol) async {
        await MainActor.run {
            RepositoryProvider.useTestingRepository(repository)
        }
        setRepository(repository)
        await loadHistoryFromRepository()
    }
}

@MainActor
private enum TestCategoryStore {
    static let shared: UserCategoryStore = {
        let defaults = UserDefaults(suiteName: "com.nissy.KippleTests.HistoryCategories")!
        let store = UserCategoryStore(defaults: defaults)
        if store.category(id: savedHistoryCategoryID) == nil {
            store.add(name: "Saved history", iconSystemName: "tag", id: savedHistoryCategoryID)
        }
        return store
    }()
}
