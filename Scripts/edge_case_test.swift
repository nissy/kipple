#!/usr/bin/env swift

import Foundation

// URL / Short Text / Long Text の分類ロジックに関するエッジケース検証

private let shortTextThreshold = 200

enum Category: String {
    case url = "URL"
    case shortText = "Short Text"
    case longText = "Long Text"
}

struct EdgeCase {
    let description: String
    let input: String
    let expected: Category
}

func classify(_ content: String) -> Category {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

    if isLikelyURL(trimmed) {
        return .url
    }

    return trimmed.count <= shortTextThreshold ? .shortText : .longText
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

let edgeCases: [EdgeCase] = [
    EdgeCase(description: "プロトコル付きURL", input: "https://example.com", expected: .url),
    EdgeCase(description: "スペースを含む疑似URL", input: "example site.com", expected: .shortText),
    EdgeCase(description: "長すぎるTLD", input: "example.toolongextension", expected: .shortText),
    EdgeCase(description: "ファイル拡張子", input: "document.pdf", expected: .shortText),
    EdgeCase(description: "ドット付き短文", input: "example.txt", expected: .shortText),
    EdgeCase(description: "IPアドレス", input: "192.168.0.1", expected: .shortText),
    EdgeCase(description: "しきい値直下", input: String(repeating: "A", count: shortTextThreshold), expected: .shortText),
    EdgeCase(description: "しきい値超過", input: String(repeating: "B", count: shortTextThreshold + 1), expected: .longText),
    EdgeCase(description: "長文テキスト", input: String(repeating: "Long text sample. ", count: 30), expected: .longText),
    EdgeCase(description: "空文字", input: "", expected: .shortText),
    EdgeCase(description: "空白のみ", input: "   ", expected: .shortText)
]

print("=== カテゴリ分類エッジケースチェック ===")
var passed = 0

for edge in edgeCases {
    let actual = classify(edge.input)
    let status = actual == edge.expected ? "✅" : "❌"
    print("\(status) \(edge.description)")
    print("   入力    : \(edge.input.prefix(80))")
    print("   期待    : \(edge.expected.rawValue)")
    print("   実際    : \(actual.rawValue)")
    if actual == edge.expected { passed += 1 }
}

print("--- 合計 \(edgeCases.count) ケース中 \(passed) ケース成功 ---")
