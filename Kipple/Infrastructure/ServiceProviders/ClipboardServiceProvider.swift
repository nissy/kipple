import Foundation

enum ClipboardServiceProvider {
    @MainActor
    static func resolve() -> ClipboardServiceProtocol {
        return ModernClipboardServiceAdapter.shared
    }
}
