import Foundation
import AppKit

enum HotkeyManagerProvider {
    @MainActor
    static func resolve() -> Any {
        // Use SimplifiedHotkeyManager for all versions
        return SimplifiedHotkeyManager.shared
    }

    // Create without MainActor requirement
    static func resolveSync() -> Any {
        // For synchronous contexts, use the legacy manager
        return HotkeyManager()
    }
}
