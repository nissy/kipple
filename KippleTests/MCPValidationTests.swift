import XCTest
@testable import Kipple

final class MCPValidationTests: XCTestCase {
    func testRejectsInvalidShapeAndFileInput() throws {
        let id = UUID().uuidString
        let invalid = [
            #"{"requestId":"ID","items":[]}"#,
            #"{"requestId":"ID","items":[{"filePath":"/a"}]}"#,
            #"{"requestId":"ID","items":[{"content":"a","filePath":"/a"}]}"#,
            #"{"requestId":"ID","items":[{"content":null}]}"#,
            #"{"requestId":"ID","items":[{"content":"a","unexpected":true}]}"#
        ]
        for json in invalid {
            XCTAssertThrowsError(try MCPInputValidation.decode(Data(json.replacingOccurrences(of: "ID", with: id).utf8)))
        }
        let request = MCPRegistration(requestId: UUID(), items: Array(repeating: .init(content: "a"), count: 50))
        XCTAssertEqual(try MCPInputValidation.decode(JSONEncoder().encode(request)).items.count, 50)
        var tooMany = request
        tooMany.items.append(.init(content: "b"))
        XCTAssertThrowsError(try MCPInputValidation.decode(JSONEncoder().encode(tooMany)))
    }

    func testUsesEightyThousandUnicodeCodePointsWithoutTruncating() throws {
        for character in ["a", "あ", "😀"] {
            let boundary = String(repeating: character, count: 80_000)
            XCTAssertEqual(try MCPInputValidation.text(boundary), boundary)
            XCTAssertThrowsError(try MCPInputValidation.text(boundary + character)) { error in
                XCTAssertEqual(error as? MCPFailure, .tooLarge)
            }
        }
        let combining = String(repeating: "e\u{301}", count: 40_000)
        XCTAssertEqual(try MCPInputValidation.text(combining), combining)
        XCTAssertThrowsError(try MCPInputValidation.text(combining + "e"))
        XCTAssertThrowsError(try MCPInputValidation.text("a\0b"))
        XCTAssertThrowsError(try MCPInputValidation.text(""))
        XCTAssertEqual(try MCPInputValidation.title("  PR\n本文  "), "PR 本文")
        XCTAssertThrowsError(try MCPInputValidation.title(String(repeating: "a", count: 121)))
    }

    func testRejectsRemovedProtectionFields() throws {
        for field in ["sensitive", "expiresAt"] {
            for value in [true, false, NSNull(), "2026-09-12T12:00:00Z"] as [Any] {
                let object: [String: Any] = [
                    "requestId": UUID().uuidString,
                    "items": [["content": "Text", field: value]]
                ]
                let data = try JSONSerialization.data(withJSONObject: object)
                XCTAssertThrowsError(try MCPInputValidation.decode(data)) { error in
                    XCTAssertEqual(error as? MCPFailure, .invalidInput)
                }
            }
        }
    }

    func testDuplicateKeepsTitleAndOriginalRegistrationDate() {
        let createdAt = Date(timeIntervalSince1970: 2_000_000_000)
        let previous = ClipMetadata(title: "Original", createdAt: createdAt, source: .clipboard)
        let merged = ClipMetadata(source: .mcp).inheritingDetails(from: previous)
        XCTAssertEqual(merged.title, "Original")
        XCTAssertEqual(merged.createdAt, createdAt)
        XCTAssertEqual(merged.source, .mcp)
        let renamed = ClipMetadata(title: "New").inheritingDetails(from: previous)
        XCTAssertEqual(renamed.title, "New")
    }

    @MainActor
    func testTitleSourceAndBodyAreSearchableAndPreviewContainsBody() {
        let item = ClipItem(
            content: "https://example.com/release", sourceApp: "MCP",
            metadata: ClipMetadata(title: "Deployment", source: .mcp)
        )
        for query in ["Deployment", "MCP", "release"] {
            XCTAssertTrue(item.matchesSearch(query))
        }
        XCTAssertEqual(ClipboardItemPopover.makePreviewText(for: item), item.content)
        XCTAssertEqual(item.fullContent, item.content)
        XCTAssertTrue(item.isActionable)
    }
}
