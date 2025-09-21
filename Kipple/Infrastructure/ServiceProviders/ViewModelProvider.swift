import Foundation

enum ViewModelProvider {
    @MainActor
    static func resolve() -> MainViewModelProtocol {
        // Use ObservableMainViewModel exclusively (macOS 14.0+ only)
        return ObservableMainViewModel()
    }

    @MainActor
    static func resolveMainViewModel() -> Any {
        return resolve()
    }
}
