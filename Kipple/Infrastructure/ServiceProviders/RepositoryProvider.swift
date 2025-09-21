import Foundation

enum RepositoryProvider {
    @MainActor
    static func resolve() -> any ClipboardRepositoryProtocol {
        // Use SwiftData exclusively (macOS 14.0+ only)
        do {
            return try SwiftDataRepository()
        } catch {
            Logger.shared.error("Failed to create SwiftDataRepository: \(error)")
            fatalError("SwiftData initialization failed: \(error)")
        }
    }
}
