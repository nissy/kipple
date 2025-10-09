//
//  VisionTextRecognitionService.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import Foundation
import Vision
import CoreGraphics

@MainActor
final class VisionTextRecognitionService: TextRecognitionServiceProtocol {
    private let recognitionLanguages: [String]
    private let minimumTextHeight: Float

    init(recognitionLanguages: [String] = ["ja", "en"], minimumTextHeight: Float = 0.015) {
        self.recognitionLanguages = recognitionLanguages
        self.minimumTextHeight = minimumTextHeight
    }

    func recognizeText(from image: CGImage) async throws -> String {
        try Task.checkCancellation()

        return try await Task.detached(priority: .userInitiated) { [recognitionLanguages, minimumTextHeight] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = minimumTextHeight
            request.recognitionLanguages = recognitionLanguages

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return ""
            }

            let lines = observations.compactMap { observation -> String? in
                observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return lines
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }.value
    }
}
