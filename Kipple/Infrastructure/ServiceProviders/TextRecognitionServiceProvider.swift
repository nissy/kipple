import Foundation

enum TextRecognitionServiceProvider {
    @MainActor
    static func resolve() -> any TextRecognitionServiceProtocol {
        VisionTextRecognitionService()
    }
}
