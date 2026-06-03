//
//  ClipboardTextFormatterTests.swift
//  KippleTests
//
//  Created by Kipple on 2026/06/03.
//

import XCTest
@testable import Kipple

final class ClipboardTextFormatterTests: XCTestCase {
    func testFormatJSONPrettyPrintsObject() throws {
        let result = try ClipboardTextFormatter.format("{\"name\":\"Kipple\",\"enabled\":true}", as: .json)

        XCTAssertEqual(
            result,
            """
            {
              "name" : "Kipple",
              "enabled" : true
            }

            """
        )
    }

    func testFormatJSONThrowsForInvalidInput() {
        XCTAssertThrowsError(try ClipboardTextFormatter.format("{invalid", as: .json)) { error in
            guard case .invalidJSON(let detail) = error as? ClipboardTextFormatter.FormatError else {
                return XCTFail("Expected invalid JSON error")
            }
            XCTAssertFalse(detail.isEmpty)
            XCTAssertTrue(
                detail.localizedCaseInsensitiveContains("line")
                    || detail.localizedCaseInsensitiveContains("column")
                    || detail.localizedCaseInsensitiveContains("character")
            )
        }
    }

    func testFormatYAMLSerializesValidInput() throws {
        let result = try ClipboardTextFormatter.format("name: Kipple\nenabled: true\n", as: .yaml)

        XCTAssertTrue(result.contains("name: Kipple"))
        XCTAssertTrue(result.contains("enabled: true"))
    }

    func testFormatYAMLPreservesJapaneseText() throws {
        let result = try ClipboardTextFormatter.format("message: こんにちは\n", as: .yaml)

        XCTAssertTrue(result.contains("こんにちは"))
        XCTAssertFalse(result.contains("\\u"))
        XCTAssertFalse(result.contains("\\U"))
    }

    func testFormatYAMLThrowsForPlainTextScalar() {
        XCTAssertThrowsError(try ClipboardTextFormatter.format("これは普通の文章です", as: .yaml)) { error in
            guard case .invalidYAML(let detail) = error as? ClipboardTextFormatter.FormatError else {
                return XCTFail("Expected invalid YAML error")
            }
            XCTAssertTrue(detail.contains("YAML"))
        }
    }

    func testFormatYAMLThrowsForInvalidInput() {
        XCTAssertThrowsError(try ClipboardTextFormatter.format("name: [", as: .yaml)) { error in
            guard case .invalidYAML(let detail) = error as? ClipboardTextFormatter.FormatError else {
                return XCTFail("Expected invalid YAML error")
            }
            XCTAssertFalse(detail.isEmpty)
            XCTAssertNotNil(detail.range(of: #"^\d+:\d+:"#, options: .regularExpression))
        }
    }
}
