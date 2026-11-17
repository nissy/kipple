import Foundation

enum TextRecognitionServiceProvider {
    @MainActor
    static func resolve() -> VisionTextRecognitionService {
        VisionTextRecognitionService()
    }
}
