#!/usr/bin/env swift

import Foundation

// カテゴリ判定ロジックの包括的検証スクリプト
// URL / Short Text / Long Text のみをサポートします。

struct TestResult {
    let description: String
    let input: String
    let expected: String
    let actual: String
    let passed: Bool
}

private let shortTextThreshold = 200

func classify(_ content: String) -> String {
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

    if text.contains(" ") || text.contains("@") || text.contains("\n") {
        return false
    }

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

func runTests(_ cases: [(description: String, input: String, expected: String)]) -> [TestResult] {
    return cases.map { testCase in
        let actual = classify(testCase.input)
        return TestResult(
            description: testCase.description,
            input: testCase.input,
            expected: testCase.expected,
            actual: actual,
            passed: actual == testCase.expected
        )
    }
}

func displayResults(_ results: [TestResult], category: String) {
    print("\n=== \(category) ===")
    for result in results {
        let status = result.passed ? "✅" : "❌"
        print("\(status) \(result.description)")
        print("   入力  : \(result.input.prefix(120))")
        print("   期待  : \(result.expected)")
        print("   実際  : \(result.actual)")
    }
    let passCount = results.filter { $0.passed }.count
    print("--- \(passCount)/\(results.count) passed ---")
}

let urlCases = [
    ("HTTPS URL", "https://example.com", "URL"),
    ("FTP URL", "ftp://ftp.example.com", "URL"),
    ("Domain without scheme", "www.example.co.jp", "URL"),
    ("Invalid TLD", "example.toolongextension", "Short Text"),
    ("Contains space", "example site.com", "Short Text"),
]

let shortTextCases = [
    ("Short memo", "Remember to call John", "Short Text"),
    ("Trimmed short", "   Quick note   ", "Short Text"),
    ("Boundary short", String(repeating: "A", count: shortTextThreshold), "Short Text"),
    ("Looks like URL but has space", "hello world.com", "Short Text"),
]

let longTextCases = [
    ("Long paragraph", String(repeating: "Long text sample. ", count: 20), "Long Text"),
    ("Boundary long", String(repeating: "B", count: shortTextThreshold + 1), "Long Text"),
]

print("ClipItem カテゴリ判定ロジックの包括的検証")
let urlResults = runTests(urlCases)
let shortResults = runTests(shortTextCases)
let longResults = runTests(longTextCases)

displayResults(urlResults, category: "URL 判定")
displayResults(shortResults, category: "Short Text 判定")
displayResults(longResults, category: "Long Text 判定")

let total = urlResults + shortResults + longResults
let passed = total.filter { $0.passed }.count
print("\n=== サマリー ===")
print("合計 \(total.count) ケース中 \(passed) ケース成功")
