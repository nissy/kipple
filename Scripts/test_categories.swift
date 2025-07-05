#!/usr/bin/env swift

import Foundation

// カテゴリ判定ロジックの検証スクリプト

struct TestCase {
    let input: String
    let expectedCategory: String
    let description: String
}

// ClipItemのカテゴリ判定ロジックを再現
func categorize(_ content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // メール判定
    if isValidEmail(trimmed) {
        return "Email"
    }
    
    // URL判定
    if isValidURL(trimmed) {
        return "URL"
    }
    
    // ファイルパス判定
    if isFilePath(trimmed) {
        return "File"
    }
    
    // コード判定
    if isCodeSnippet(trimmed) {
        return "Code"
    }
    
    // 文字数による分類
    if content.count <= 50 {
        return "Short"
    } else if content.count <= 500 {
        return "General"
    } else {
        return "Long"
    }
}

func isValidURL(_ text: String) -> Bool {
    // 明確なURLプロトコル
    if text.hasPrefix("http://") || text.hasPrefix("https://") || 
       text.hasPrefix("ftp://") || text.hasPrefix("file://") {
        return true
    }
    
    // より厳密なドメイン形式のチェック
    if !text.contains(" ") && text.count < 200 {
        let components = text.components(separatedBy: ".")
        if components.count >= 2 {
            // 最後の要素がTLD（2-6文字の英字）であることを確認
            let lastComponent = components.last ?? ""
            let tldPattern = "^[a-zA-Z]{2,6}$"
            if lastComponent.range(of: tldPattern, options: .regularExpression) != nil {
                // 最初の要素が妥当なドメイン名であることを確認
                let firstComponent = components.first ?? ""
                let domainPattern = "^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$"
                if firstComponent.range(of: domainPattern, options: .regularExpression) != nil ||
                   firstComponent.count >= 2 {
                    return true
                }
            }
        }
    }
    
    return false
}

func isValidEmail(_ text: String) -> Bool {
    if text.contains(" ") || text.count > 100 {
        return false
    }
    
    let emailPattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
    if text.range(of: emailPattern, options: .regularExpression) != nil {
        return true
    }
    
    return false
}

func isFilePath(_ text: String) -> Bool {
    // 絶対パスまたは相対パス
    if text.hasPrefix("/") || text.hasPrefix("~/") || 
       text.hasPrefix("./") || text.hasPrefix("../") {
        return true
    }
    
    // Windowsパス
    if text.count > 2 && text.dropFirst().hasPrefix(":\\") {
        return true
    }
    
    return false
}

func isCodeSnippet(_ text: String) -> Bool {
    // プログラミング言語の典型的なパターン
    let codePatterns = [
        // 関数・メソッド定義
        "func\\s+\\w+", "function\\s+\\w+", "def\\s+\\w+",
        // クラス・構造体定義
        "class\\s+\\w+", "struct\\s+\\w+", "interface\\s+\\w+",
        // 変数定義
        "var\\s+\\w+", "let\\s+\\w+", "const\\s+\\w+",
        // 制御構造
        "if\\s*\\(", "for\\s*\\(", "while\\s*\\(",
        // その他の言語構造
        "import\\s+\\w+", "#include", "using\\s+namespace"
    ]
    
    for pattern in codePatterns {
        if text.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
    }
    
    // 複数のコード記号を含む場合
    let codeSymbols = ["{", "}", "[", "]", ";", "=>", "->", "==", "!=", "&&", "||", "++", "--"]
    let symbolCount = codeSymbols.filter { text.contains($0) }.count
    if symbolCount >= 2 {
        return true
    }
    
    return false
}

// テストケース実行
let testCases: [TestCase] = [
    // URL判定の問題ケース
    TestCase(input: "example.txt", expectedCategory: "Short", description: "単純なファイル名"),
    TestCase(input: "version.1.0", expectedCategory: "Short", description: "バージョン番号"),
    TestCase(input: "3.14159", expectedCategory: "Short", description: "小数"),
    TestCase(input: "Mr. Smith", expectedCategory: "Short", description: "ピリオドを含む名前"),
    TestCase(input: "192.168.1.1", expectedCategory: "Short", description: "IPアドレス"),
    
    // メール判定の問題ケース
    TestCase(input: "user@", expectedCategory: "Short", description: "不完全なメール"),
    TestCase(input: "@example.com", expectedCategory: "Short", description: "ユーザー名なし"),
    TestCase(input: "user..name@example.com", expectedCategory: "Short", description: "連続ピリオド"),
    
    // コード判定の問題ケース
    TestCase(input: "Let me explain", expectedCategory: "Short", description: "通常のテキスト with 'let'"),
    TestCase(input: "The function works", expectedCategory: "Short", description: "通常のテキスト with 'function'"),
    
    // ファイルパス判定の問題ケース
    TestCase(input: "C: drive is full", expectedCategory: "Short", description: "Windowsドライブ言及"),
    TestCase(input: "D:\\Projects\\MyApp\\src", expectedCategory: "File", description: "Windowsパス"),
    TestCase(input: "E:\\file.txt", expectedCategory: "File", description: "Windowsパス")
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
    print("   入力: '\(testCase.input)'")
    print("   期待: \(testCase.expectedCategory)")
    print("   実際: \(actual)")
    print()
}

print(String(repeating: "=", count: 60))
print("結果: \(passCount) passed, \(failCount) failed")