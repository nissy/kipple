#!/usr/bin/env swift

import Foundation

// カテゴリ判定ロジックの包括的検証スクリプト

struct TestResult {
    let input: String
    let expected: String
    let actual: String
    let passed: Bool
    let description: String
}

// ClipItemのカテゴリ判定ロジックを再現（実装と同一）
func categorize(_ content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // メール判定（URL判定より先に）
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
    
    // コード判定（簡易的）
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

// URL判定を改善
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

// メール判定を改善
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

// ファイルパス判定を改善
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

// コード判定を改善
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

// テストケースを実行する関数
func runTests(_ testCases: [(input: String, expected: String, description: String)]) -> [TestResult] {
    return testCases.map { testCase in
        let actual = categorize(testCase.input)
        let passed = actual == testCase.expected
        return TestResult(
            input: testCase.input,
            expected: testCase.expected,
            actual: actual,
            passed: passed,
            description: testCase.description
        )
    }
}

// カテゴリ別にテスト結果を表示
func displayResults(_ results: [TestResult], category: String) {
    print("\n=== \(category) ===")
    
    let failures = results.filter { !$0.passed }
    let passes = results.filter { $0.passed }
    
    if failures.isEmpty {
        print("✅ すべてのテストケースが成功しました (\(passes.count)件)")
    } else {
        print("❌ \(failures.count)/\(results.count) 件のテストケースが失敗しました")
        print("\n失敗したケース:")
        for failure in failures {
            print("  - \(failure.description)")
            print("    入力: '\(failure.input)'")
            print("    期待: \(failure.expected), 実際: \(failure.actual)")
        }
    }
}

// メインの実行部分
print("ClipItem カテゴリ判定ロジックの包括的検証")
print(String(repeating: "=", count: 60))

// URL判定テストケース
let urlTests = [
    // 正しくURLと判定されるべきケース
    ("https://www.example.com", "URL", "完全なHTTPS URL"),
    ("http://example.com", "URL", "HTTPプロトコル付きURL"),
    ("ftp://files.example.com", "URL", "FTPプロトコル"),
    ("file:///Users/example/file.txt", "URL", "ファイルプロトコル"),
    ("example.com", "URL", "プロトコルなしドメイン"),
    ("www.example.com", "URL", "wwwサブドメイン"),
    ("subdomain.example.co.jp", "URL", "日本のccTLD"),
    ("test-domain.com", "URL", "ハイフン含むドメイン"),
    
    // URLと判定されるべきでないケース
    ("example.txt", "URL", "ファイル拡張子（問題：URLと誤判定）"),
    ("version.1.0", "Short", "バージョン番号"),
    ("3.14159", "Short", "小数"),
    ("Mr. Smith", "Short", "人名"),
    ("192.168.1.1", "Short", "IPアドレス"),
    ("hello world.com", "Short", "スペース含むテキスト"),
    (".com", "Short", "TLDのみ"),
    ("example.", "Short", "不完全なドメイン"),
    ("@example.com", "URL", "メール風（問題：URLと誤判定）"),
    ("E:\\file.txt", "URL", "Windowsパス（問題：URLと誤判定）")
]

// メール判定テストケース
let emailTests = [
    // 正しくメールと判定されるべきケース
    ("user@example.com", "Email", "標準的なメール"),
    ("user.name@example.com", "Email", "ピリオド含むユーザー名"),
    ("user+tag@example.com", "Email", "プラス記号付き"),
    ("user_name@example.com", "Email", "アンダースコア"),
    ("123@example.com", "Email", "数字のみのユーザー名"),
    
    // メールと判定されるべきでないケース
    ("user@", "Short", "ドメインなし"),
    ("@example.com", "URL", "@で始まる（問題：URLと判定）"),
    ("user example.com", "Short", "@なし"),
    ("user @example.com", "Short", "スペースあり"),
    ("user..name@example.com", "Email", "連続ピリオド（問題：メールと誤判定）"),
    ("user@example", "Short", "TLDなし")
]

// コード判定テストケース
let codeTests = [
    // 正しくコードと判定されるべきケース
    ("func greet() { }", "Code", "Swift関数"),
    ("function add(a, b) { return a + b; }", "Code", "JavaScript関数"),
    ("if (x > 0) { print(x) }", "Code", "条件文"),
    ("class Person { }", "Code", "クラス定義"),
    ("import Foundation", "Code", "import文"),
    ("[1, 2, 3].map { $0 * 2 }", "Code", "クロージャ"),
    
    // コードと判定されるべきでないケース
    ("Let me explain", "Short", "Let で始まる文"),
    ("The function works", "Code", "function を含む文（問題：コードと誤判定）"),
    ("Variable weather", "Short", "Variable で始まる文"),
    ("Class starts at 9", "Short", "Class で始まる文")
]

// ファイルパス判定テストケース
let filePathTests = [
    // 正しくファイルパスと判定されるべきケース
    ("/Users/example/file.txt", "File", "絶対パス"),
    ("~/Documents/report.pdf", "File", "ホームディレクトリ"),
    ("./src/main.swift", "File", "相対パス"),
    ("../parent/file.txt", "File", "親ディレクトリ"),
    ("C:\\Windows\\System32", "File", "Windowsパス"),
    ("D:\\file.txt", "File", "Windowsドライブ"),
    
    // ファイルパスと判定されるべきでないケース
    ("file.txt", "URL", "パス区切りなし（問題：URLと判定）"),
    ("example/file", "Short", "相対パス記号なし"),
    ("C: drive is full", "Short", "ドライブ言及のみ")
]

// 文字数分類テストケース
let lengthTests = [
    ("Hello", "Short", "5文字"),
    (String(repeating: "a", count: 50), "Short", "50文字（境界値）"),
    (String(repeating: "a", count: 51), "General", "51文字"),
    (String(repeating: "a", count: 500), "General", "500文字（境界値）"),
    (String(repeating: "a", count: 501), "Long", "501文字")
]

// 各カテゴリのテストを実行
let urlResults = runTests(urlTests)
let emailResults = runTests(emailTests)
let codeResults = runTests(codeTests)
let filePathResults = runTests(filePathTests)
let lengthResults = runTests(lengthTests)

// 結果表示
displayResults(urlResults, category: "URL判定テスト")
displayResults(emailResults, category: "メール判定テスト")
displayResults(codeResults, category: "コード判定テスト")
displayResults(filePathResults, category: "ファイルパス判定テスト")
displayResults(lengthResults, category: "文字数分類テスト")

// 総合結果
print("\n" + String(repeating: "=", count: 60))
let allResults = urlResults + emailResults + codeResults + filePathResults + lengthResults
let totalPassed = allResults.filter { $0.passed }.count
let totalFailed = allResults.filter { !$0.passed }.count
print("総合結果: \(totalPassed)/\(allResults.count) 成功, \(totalFailed) 失敗")

// 主な問題点のサマリー
print("\n主な問題点:")
print("1. URL判定が過度に寛容（ファイル拡張子をURLと誤判定）")
print("2. メールアドレスの検証が不十分（連続ピリオドを許可）")
print("3. コード判定で自然言語の文脈を考慮していない")
print("4. 判定の優先順位に改善の余地あり")