import Foundation
import AppKit

enum HotkeyManagerProvider {
    @MainActor
    static func resolve() -> Any {
        // Use SimplifiedHotkeyManager singleton for all cases
        return SimplifiedHotkeyManager.shared
    }

    // Create without MainActor requirement
    static func resolveSync() -> Any {
        // Use SimplifiedHotkeyManager singleton for all cases
        return SimplifiedHotkeyManager.shared
    }
}
