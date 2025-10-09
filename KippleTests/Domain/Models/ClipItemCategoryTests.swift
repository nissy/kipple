//
//  ClipItemCategoryTests.swift
//  KippleTests
//

import XCTest
@testable import Kipple

@MainActor
final class ClipItemCategoryTests: XCTestCase {
    func testURLDetection() {
        let urls = [
            "https://www.example.com",
            "http://example.com",
            "https://example.com/path/to/page",
            "http://example.com:8080",
            "https://example.com/path?query=value",
            "https://example.com/path#fragment",
            "ftp://files.example.com",
            "file:///Users/example/file.txt",
            "www.example.com",
            "subdomain.example.co.jp",
            "api.github.com"
        ]

        for url in urls {
            let item = ClipItem(content: url)
            XCTAssertEqual(item.category, .url, "'\(url)' should be categorized as URL")
        }
    }

    func testURLFalsePositives() {
        let nonURLs = [
            "example.txt",
            "version.1.0",
            "3.14159",
            "Mr. Smith",
            "hello world.com",
            "example.",
            "example.toolongextension",
            "example.123",
            "-example.com",
            "example-.com",
            "Swift 5.0 is great.",
            "192.168.1.1",
            "image.png",
            "transaction.go",
            "notes.pg.hcl"
        ]

        for text in nonURLs {
            let item = ClipItem(content: text)
            XCTAssertNotEqual(item.category, .url, "'\(text)' should NOT be categorized as URL")
        }
    }

    func testNonURLClassificationReturnsAll() {
        let samples = [
            "Quick note",
            String(repeating: "A", count: 50),
            "Line one\nLine two",
            String(repeating: "Long text sample. ", count: 20),
            "https://not-a-url because of space"
        ]

        for text in samples {
            let item = ClipItem(content: text)
            XCTAssertEqual(item.category, .all, "'\(text)' should be categorized as All/None")
        }
    }

    func testCachingUsesRawValue() {
        let cache = CategoryClassifierCache.shared
        cache.set(.all, for: "cached text")
        XCTAssertEqual(cache.get(for: "cached text"), .all)
    }
}
