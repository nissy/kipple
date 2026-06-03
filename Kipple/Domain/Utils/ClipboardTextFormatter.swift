//
//  ClipboardTextFormatter.swift
//  Kipple
//
//  Created by Kipple on 2026/06/03.
//

import Foundation
import Yams

enum ClipboardTextFormat: String, CaseIterable, Hashable {
    case json
    case yaml

    var localizedName: String {
        switch self {
        case .json:
            return "JSON"
        case .yaml:
            return "YAML"
        }
    }
}

enum ClipboardTextFormatter {
    enum FormatError: Error, Equatable {
        case emptyInput
        case invalidJSON(String)
        case invalidYAML(String)
        case outputEncodingFailed

        var detail: String {
            switch self {
            case .emptyInput:
                return NSLocalizedString("editor.format.error.empty", comment: "Empty format input error")
            case .invalidJSON(let detail), .invalidYAML(let detail):
                return detail
            case .outputEncodingFailed:
                return NSLocalizedString("editor.format.error.output", comment: "Format output encoding error")
            }
        }
    }

    static func format(_ text: String, as format: ClipboardTextFormat) throws -> String {
        switch format {
        case .json:
            return try formatJSON(text)
        case .yaml:
            return try formatYAML(text)
        }
    }

    private static func formatJSON(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FormatError.emptyInput
        }
        guard let data = text.data(using: .utf8) else {
            throw FormatError.invalidJSON(
                NSLocalizedString("editor.format.error.utf8", comment: "Format UTF-8 conversion error")
            )
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data)
            let formattedData = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .withoutEscapingSlashes]
            )
            guard let formattedText = String(data: formattedData, encoding: .utf8) else {
                throw FormatError.outputEncodingFailed
            }
            return formattedText + "\n"
        } catch let error as FormatError {
            throw error
        } catch let error as NSError {
            throw FormatError.invalidJSON(jsonErrorDetail(from: error))
        } catch {
            throw FormatError.invalidJSON(error.localizedDescription)
        }
    }

    private static func formatYAML(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FormatError.emptyInput
        }

        do {
            guard let node = try Yams.compose(yaml: text) else {
                throw FormatError.emptyInput
            }
            guard isStructuredYAMLNode(node) else {
                throw FormatError.invalidYAML(
                    NSLocalizedString("editor.format.error.yaml.structure", comment: "YAML structure format error")
                )
            }
            return try Yams.serialize(node: node, allowUnicode: true)
        } catch let error as FormatError {
            throw error
        } catch {
            throw FormatError.invalidYAML(String(describing: error))
        }
    }

    private static func isStructuredYAMLNode(_ node: Node) -> Bool {
        switch node {
        case .mapping, .sequence:
            return true
        case .scalar, .alias:
            return false
        }
    }

    private static func jsonErrorDetail(from error: NSError) -> String {
        if let debugDescription = error.userInfo[NSDebugDescriptionErrorKey] as? String {
            return debugDescription
        }
        return error.localizedDescription
    }
}
