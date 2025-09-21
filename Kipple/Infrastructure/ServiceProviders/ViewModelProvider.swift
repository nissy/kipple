import Foundation

enum ViewModelProvider {
    @MainActor
    static func resolve() -> MainViewModelProtocol {
        // Use ObservableMainViewModel for macOS 14.0+ by default
        if #available(macOS 14.0, *) {
            return ObservableMainViewModel()
        } else {
            return MainViewModel()
        }
    }

    @MainActor
    static func resolveMainViewModel() -> Any {
        return resolve()
    }
}
