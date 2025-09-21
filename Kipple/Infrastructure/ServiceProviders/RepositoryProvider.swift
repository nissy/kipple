import Foundation

enum RepositoryProvider {
    @MainActor
    static func resolve() -> any ClipboardRepositoryProtocol {
        // SwiftData is the default for macOS 14.0+
        if #available(macOS 14.0, *) {
            do {
                return try SwiftDataRepository()
            } catch {
                Logger.shared.error("Failed to create SwiftDataRepository: \(error)")
                // Fallback to Core Data if SwiftData fails
                return CoreDataClipboardRepository()
            }
        } else {
            // Use Core Data for older macOS versions
            return CoreDataClipboardRepository()
        }
    }
}
