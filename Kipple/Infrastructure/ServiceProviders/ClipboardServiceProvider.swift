import Foundation

enum ClipboardServiceProvider {
    @MainActor
    static func resolve() -> ClipboardServiceProtocol {
        if #available(macOS 13.0, *) {
            return ModernClipboardServiceAdapter.shared
        } else {
            return ClipboardService.shared
        }
    }
}
