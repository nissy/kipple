#!/usr/bin/env swift

import Foundation

// エッジケースの詳細検証

func categorize(_ content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    
    if isValidEmail(trimmed) { return "Email" }
    if isValidURL(trimmed) { return "URL" }
    if isFilePath(trimmed) { return "File" }
    if isCodeSnippet(trimmed) { return "Code" }
    
    if content.count <= 50 { return "Short" }
    else if content.count <= 500 { return "General" }
    else { return "Long" }
}

func isValidURL(_ text: String) -> Bool {
    if text.hasPrefix("http://") || text.hasPrefix("https://") || 
       text.hasPrefix("ftp://") || text.hasPrefix("file://") {
        return true
    }
    
    if !text.contains(" ") && text.count < 200 {
        let components = text.components(separatedBy: ".")
        if components.count >= 2 {
            let lastComponent = components.last ?? ""
            let tldPattern = "^[a-zA-Z]{2,6}$"
            if lastComponent.range(of: tldPattern, options: .regularExpression) != nil {
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
    if text.hasPrefix("/") || text.hasPrefix("~/") || 
       text.hasPrefix("./") || text.hasPrefix("../") {
        return true
    }
    
    if text.count > 2 && text.dropFirst().hasPrefix(":\\") {
        return true
    }
    
    return false
}

func isCodeSnippet(_ text: String) -> Bool {
    let codePatterns = [
        "func\\s+\\w+", "function\\s+\\w+", "def\\s+\\w+",
        "class\\s+\\w+", "struct\\s+\\w+", "interface\\s+\\w+",
        "var\\s+\\w+", "let\\s+\\w+", "const\\s+\\w+",
        "if\\s*\\(", "for\\s*\\(", "while\\s*\\(",
        "import\\s+\\w+", "#include", "using\\s+namespace"
    ]
    
    for pattern in codePatterns {
        if text.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
    }
    
    let codeSymbols = ["{", "}", "[", "]", ";", "=>", "->", "==", "!=", "&&", "||", "++", "--"]
    let symbolCount = codeSymbols.filter { text.contains($0) }.count
    if symbolCount >= 2 {
        return true
    }
    
    return false
}

// エッジケースの定義
struct EdgeCase {
    let input: String
    let description: String
    let expectedBehavior: String
}

let edgeCases = [
    // URLパターンの境界ケース
    EdgeCase(
        input: "example.pdf",
        description: "一般的なファイル拡張子",
        expectedBehavior: "ファイル拡張子はURLと判定されるべきではない"
    ),
    EdgeCase(
        input: "report.docx",
        description: "Word文書拡張子",
        expectedBehavior: "文書ファイルはURLではない"
    ),
    EdgeCase(
        input: "image.png",
        description: "画像ファイル拡張子",
        expectedBehavior: "画像ファイルはURLではない"
    ),
    EdgeCase(
        input: "archive.zip",
        description: "圧縮ファイル拡張子",
        expectedBehavior: "圧縮ファイルはURLではない"
    ),
    EdgeCase(
        input: "a.b",
        description: "最小構成のドット区切り",
        expectedBehavior: "単純すぎる構造はURLではない"
    ),
    EdgeCase(
        input: "localhost:8080",
        description: "ローカルホストとポート",
        expectedBehavior: "localhostパターンの扱い"
    ),
    EdgeCase(
        input: "10.0.0.1",
        description: "プライベートIPアドレス",
        expectedBehavior: "IPアドレスはURLとして扱わない"
    ),
    
    // パス形式の曖昧なケース
    EdgeCase(
        input: "/Users/john.doe/file.txt",
        description: "ドットを含むユーザー名のパス",
        expectedBehavior: "明確なパス形式はファイルパスと判定"
    ),
    EdgeCase(
        input: "~/john.doe@company/docs",
        description: "@を含むディレクトリ名",
        expectedBehavior: "パス形式が優先される"
    ),
    EdgeCase(
        input: "C:\\Users\\test@example.com\\file",
        description: "メールアドレス風のWindowsパス",
        expectedBehavior: "Windowsパス形式が優先"
    ),
    
    // コードパターンの境界ケース
    EdgeCase(
        input: "if you want to import this module",
        description: "importを含む自然言語",
        expectedBehavior: "文章はコードと判定されない"
    ),
    EdgeCase(
        input: "The class will start at 9 AM",
        description: "classを含む自然言語",
        expectedBehavior: "文章はコードと判定されない"
    ),
    EdgeCase(
        input: "x == y",
        description: "単純な等式",
        expectedBehavior: "数式表現の扱い"
    ),
    EdgeCase(
        input: "price > 100 && quantity < 50",
        description: "論理式風のテキスト",
        expectedBehavior: "論理演算子を含む"
    ),
    
    // 特殊文字と空白
    EdgeCase(
        input: "  example.com  ",
        description: "前後に空白があるURL",
        expectedBehavior: "トリムされてURLと判定"
    ),
    EdgeCase(
        input: "\tuser@example.com\n",
        description: "タブと改行を含むメール",
        expectedBehavior: "トリムされてメールと判定"
    ),
    EdgeCase(
        input: "",
        description: "空文字列",
        expectedBehavior: "Shortと判定"
    ),
    EdgeCase(
        input: "   ",
        description: "空白のみ",
        expectedBehavior: "トリム後空になりShortと判定"
    )
]

// テスト実行と結果表示
print("エッジケース検証結果")
print(String(repeating: "=", count: 80))
print()

for (index, testCase) in edgeCases.enumerated() {
    let result = categorize(testCase.input)
    
    print("[\(index + 1)] \(testCase.description)")
    print("    入力: '\(testCase.input)'")
    print("    判定結果: \(result)")
    print("    期待される動作: \(testCase.expectedBehavior)")
    
    // 問題のある判定を特定
    var issue = ""
    if testCase.input.hasSuffix(".pdf") || testCase.input.hasSuffix(".docx") || 
       testCase.input.hasSuffix(".png") || testCase.input.hasSuffix(".zip") {
        if result == "URL" {
            issue = "❌ 問題: ファイル拡張子がURLと誤判定"
        }
    }
    
    if testCase.input.lowercased().contains("class") && 
       testCase.description.contains("自然言語") && result == "Code" {
        issue = "❌ 問題: 自然言語がコードと誤判定"
    }
    
    if !issue.isEmpty {
        print("    \(issue)")
    }
    
    print()
}

// 追加の診断情報
print(String(repeating: "=", count: 80))
print("\n診断情報:")
print("\n1. ドメイン判定の詳細チェック:")
let testDomains = ["a.b", "ab.cd", "example.txt", "test.co", "my.domain"]
for domain in testDomains {
    let components = domain.components(separatedBy: ".")
    let lastComponent = components.last ?? ""
    let firstComponent = components.first ?? ""
    print("   '\(domain)': first='\(firstComponent)' last='\(lastComponent)' -> \(categorize(domain))")
}

print("\n2. 曖昧なパターンの判定優先順位:")
let ambiguousPatterns = [
    "user@server:/path/to/file",  // SSH形式
    "http://user@example.com",     // Basic認証URL
    "file:///C:/Users/test.txt",   // fileプロトコル
    "/var/log/app.log",            // 絶対パス
    "import { Component } from 'react'"  // ES6 import
]

for pattern in ambiguousPatterns {
    print("   '\(pattern)' -> \(categorize(pattern))")
}