#!/usr/bin/env swift

import Foundation

// カテゴリ判定ロジックの簡易検証スクリプト（URL / Short Text / Long Text）

struct TestCase {
    let input: String
    let expectedCategory: String
    let description: String
}

private let shortTextThreshold = 200

func categorize(_ content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

    if isLikelyURL(trimmed) {
        return "URL"
    }

    return trimmed.count <= shortTextThreshold ? "Short Text" : "Long Text"
}

func isLikelyURL(_ text: String) -> Bool {
    guard text.count >= 4 else { return false }

    if text.hasPrefix("http://") || text.hasPrefix("https://") ||
        text.hasPrefix("ftp://") || text.hasPrefix("file://") {
        return true
    }

    if text.contains(" ") || text.contains("@") { return false }

    let components = text.split(separator: ".")
    guard components.count >= 2, components.count <= 4 else { return false }
    guard let tld = components.last, (2...10).contains(tld.count) else { return false }

    let tldPattern = "^[A-Za-z]{2,10}$"
    guard tld.range(of: tldPattern, options: .regularExpression) != nil else { return false }

    let domainPattern = "^[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]$"
    for component in components.dropLast() {
        if component.count < 1 ||
            component.range(of: domainPattern, options: .regularExpression) == nil {
            return false
        }
    }

    return true
}

let testCases: [TestCase] = [
    // URL detection
    TestCase(input: "https://example.com", expectedCategory: "URL", description: "HTTPS URL"),
    TestCase(input: "ftp://files.example.com", expectedCategory: "URL", description: "FTP URL"),
    TestCase(input: "www.example.co.jp", expectedCategory: "URL", description: "Domain without scheme"),

    // Non URL short texts
    TestCase(input: "Remember to call John", expectedCategory: "Short Text", description: "Short memo"),
    TestCase(input: "   Trimmed short text   ", expectedCategory: "Short Text", description: "Whitespace trimmed"),
    TestCase(input: "hello world.com", expectedCategory: "Short Text", description: "Contains space"),

    // Long text
    TestCase(input: String(repeating: "Long text sample. ", count: 20), expectedCategory: "Long Text", description: "Long paragraph"),
    TestCase(input: String(repeating: "A", count: shortTextThreshold + 1), expectedCategory: "Long Text", description: "Boundary over threshold"),

    // Boundary exact threshold (Short)
    TestCase(input: String(repeating: "B", count: shortTextThreshold), expectedCategory: "Short Text", description: "Boundary equals threshold"),

    // URL false positive guards
    TestCase(input: "example.txt", expectedCategory: "Short Text", description: "File extension"),
    TestCase(input: "192.168.1.1", expectedCategory: "Short Text", description: "IP address"),
    TestCase(input: "example.toolongextension", expectedCategory: "Short Text", description: "Invalid TLD"),
]

print("カテゴリ判定テスト結果:")
print(String(repeating: "=", count: 60))

var passCount = 0
var failCount = 0

for testCase in testCases {
    let actual = categorize(testCase.input)
    let passed = actual == testCase.expectedCategory

    if passed {
        passCount += 1
        print("✅ PASS: \(testCase.description)")
    } else {
        failCount += 1
        print("❌ FAIL: \(testCase.description)")
    }
    print("   入力: '\(testCase.input.prefix(80))'")
    print("   期待: \(testCase.expectedCategory)")
    print("   実際: \(actual)")
    print()
}

print(String(repeating: "=", count: 60))
print("結果: \(passCount) passed, \(failCount) failed")
