import Foundation

enum RepositoryProvider {
    @MainActor
    private static var overrideRepository: (any ClipboardRepositoryProtocol)?

    @MainActor
    static func resolve() -> any ClipboardRepositoryProtocol {
        if let overrideRepository {
            return overrideRepository
        }
        // Use SwiftData exclusively (macOS 14.0+ only)
        do {
            return try SwiftDataRepository.make()
        } catch {
            Logger.shared.error("Failed to create SwiftDataRepository: \(error)")
            fatalError("SwiftData initialization failed: \(error)")
        }
    }

    @MainActor
    static func useTestingRepository(_ repository: (any ClipboardRepositoryProtocol)?) {
        overrideRepository = repository
    }
}
