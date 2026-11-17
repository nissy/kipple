//
//  VisionTextRecognitionService.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import AppKit
import Vision

@MainActor
final class VisionTextRecognitionService: TextRecognitionServiceProtocol {
    typealias PerformRequest = @MainActor (RecognizeDocumentsRequest, CGImage) async throws -> [DocumentObservation]

    enum RequestPhase: String {
        case prewarm
        case recognition
    }

    private static let minimumTextHeightPixels: Float = 8
    private let recognitionLanguages: [String]
    private let minimumTextHeight: Float
    private let onCancellation: (RequestPhase) -> Void
    private let performRequest: PerformRequest
    private var prewarmTask: Task<Void, Never>?

    init(
        recognitionLanguages: [String] = ["ja", "en"],
        minimumTextHeight: Float = 0.015,
        onCancellation: @escaping (RequestPhase) -> Void = { SystemDiagnostics.ocrCancellation(phase: $0.rawValue) },
        performRequest: @escaping PerformRequest = { request, image in try await request.perform(on: image) }
    ) {
        self.recognitionLanguages = recognitionLanguages
        self.minimumTextHeight = minimumTextHeight
        self.onCancellation = onCancellation
        self.performRequest = performRequest
    }

    func prewarm() {
        guard prewarmTask == nil else { return }
        prewarmTask = Task(priority: .utility) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard let image = Self.makePrewarmImage() else {
                Logger.shared.warning("Could not create the OCR warm-up image.")
                return
            }
            do {
                _ = try await perform(for: image, phase: .prewarm)
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return }
                Logger.shared.warning("OCR model warm-up failed: \(error.localizedDescription)")
            }
        }
    }

    func recognizeText(from image: CGImage) async throws -> String {
        if !Task.isCancelled { prewarmTask?.cancel() }
        let observations = try await perform(for: image, phase: .recognition)
        return observations.map { observation in
            let document = observation.document
            let paragraphs = document.paragraphs.map {
                OCRDocumentFormatter.Paragraph(
                    text: $0.transcript, bounds: $0.boundingRegion.boundingBox.cgRect,
                    lineIDs: Set($0.lines.map(\.uuid))
                )
            }
            let tables = document.tables.map { table in
                OCRDocumentFormatter.Table(
                    cells: table.rows.flatMap { row in
                        row.map {
                            OCRDocumentFormatter.Cell(
                                text: $0.content.text.transcript, rows: $0.rowRange, columns: $0.columnRange
                            )
                        }
                    },
                    bounds: table.boundingRegion.boundingBox.cgRect,
                    lineIDs: Set(table.rows.flatMap { $0 }.flatMap { $0.content.text.lines.map(\.uuid) })
                )
            }
            let listLineIDs = Set(document.lists.flatMap { $0.items }.flatMap { $0.content.text.lines.map(\.uuid) })
            return OCRDocumentFormatter.text(
                paragraphs: paragraphs, tables: tables, listLineIDs: listLineIDs, fallback: document.text.transcript
            )
        }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")
    }

    private func perform(for image: CGImage, phase: RequestPhase) async throws -> [DocumentObservation] {
        do {
            try Task.checkCancellation()
            let observations = try await performRequest(makeRequest(for: image), image)
            try Task.checkCancellation()
            return observations
        } catch {
            if Task.isCancelled || Self.isCancellation(error) { onCancellation(phase) }
            throw error
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? VisionError, case .requestCancelled = error { return true }
        let error = error as NSError
        return error.domain == VNErrorDomain && error.code == VNErrorCode.requestCancelled.rawValue
    }

    private func makeRequest(for image: CGImage) -> RecognizeDocumentsRequest {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = recognitionLanguages.map { Locale.Language(identifier: $0) }
        request.textRecognitionOptions.minimumTextHeightFraction = min(
            minimumTextHeight, Self.minimumTextHeightPixels / Float(image.height)
        )
        request.textRecognitionOptions.useLanguageCorrection = true
        request.barcodeDetectionOptions.enabled = false
        return request
    }

    private static func makePrewarmImage() -> CGImage? {
        let image = NSImage(size: NSSize(width: 320, height: 112), flipped: false) { bounds in
            NSColor.white.setFill()
            bounds.fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black
            ]
            ("画面の文字を読み取ります" as NSString).draw(at: NSPoint(x: 12, y: 66), withAttributes: attributes)
            ("Screen Text Capture 123" as NSString).draw(at: NSPoint(x: 12, y: 18), withAttributes: attributes)
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
