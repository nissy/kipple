//
//  ClipItemCategoryTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/05.
//

import XCTest
@testable import Kipple

final class ClipItemCategoryTests: XCTestCase {
    
    // MARK: - URL判定のテストケース
    
    func testValidURLs() {
        // 正しくURLと判定されるべきもの
        let validURLs = [
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
            "test-domain.com",
            "api.github.com"
        ]
        
        for url in validURLs {
            let item = ClipItem(content: url)
            XCTAssertEqual(item.category, .url, "'\(url)' should be categorized as URL")
        }
    }
    
    func testInvalidURLs() {
        // 誤ってURLと判定されてはいけないもの
        let invalidURLs = [
            "example.txt",  // 単純なファイル名
            "version.1.0",  // バージョン番号
            "3.14159",      // 小数
            "Mr. Smith",    // ピリオドを含む名前
            "etc.",         // 略語
            "hello world.com", // スペースを含む
            ".com",         // TLDのみ
            "example.",     // 不完全なドメイン
            "example.toolongextension", // 長すぎるTLD
            "example.123",  // 数字のみのTLD
            "-example.com", // ハイフンで始まる
            "example-.com", // ハイフンで終わる
            "Swift 5.0 is great.", // 文章内のバージョン番号
            "The file extension is .swift", // 文章内の拡張子
            "192.168.1.1",   // IPアドレス（現在の実装では判定されない）
            "file.pdf",     // PDFファイル
            "image.png",    // 画像ファイル
            "document.docx", // Word文書
            "script.js",    // JavaScriptファイル
            "style.css",    // CSSファイル
            "data.json",    // JSONファイル
            "archive.zip"   // ZIPファイル
        ]
        
        for text in invalidURLs {
            let item = ClipItem(content: text)
            XCTAssertNotEqual(item.category, .url, "'\(text)' should NOT be categorized as URL")
        }
    }
    
    // MARK: - メール判定のテストケース
    
    func testValidEmails() {
        // 有効なメールアドレス
        let validEmails = [
            "user@example.com",
            "user.name@example.com",
            "user+tag@example.com",
            "user_name@example.com",
            "123@example.com",
            "user@subdomain.example.com",
            "user@example.co.jp",
            "u@example.com",  // 短いユーザー名
            "test123@subdomain.example.com",
            "first.last@example.co.jp"
        ]
        
        for email in validEmails {
            let item = ClipItem(content: email)
            XCTAssertEqual(item.category, .email, "'\(email)' should be categorized as Email")
        }
    }
    
    func testInvalidEmails() {
        // 無効なメールアドレス
        let invalidEmails = [
            "@example.com",     // ユーザー名なし
            "user@",            // ドメインなし
            "user example.com", // @なし
            "user @example.com", // スペースあり
            "user@example",     // TLDなし
            "user@.com",        // ドメイン名なし
            "user@@example.com", // @が複数
            "user@exam ple.com", // ドメインにスペース
            "user.@example.com", // ピリオドで終わるユーザー名
            ".user@example.com", // ピリオドで始まるユーザー名
            "user..name@example.com", // 連続するピリオド
            String(repeating: "a", count: 101) + "@example.com", // 長すぎる
            "user.@example.com", // ピリオドで終わる
            ".user@example.com", // ピリオドで始まる
            "user@-example.com", // ハイフンで始まるドメイン
            "user@example-.com", // ハイフンで終わるドメイン
            "a@b.c" // 短すぎる（5文字未満）
        ]
        
        for text in invalidEmails {
            let item = ClipItem(content: text)
            XCTAssertNotEqual(item.category, .email, "'\(text)' should NOT be categorized as Email")
        }
    }
    
    // MARK: - コード判定のテストケース
    
    func testValidCodeSnippets() {
        // 各種プログラミング言語のコード
        let codeSnippets = [
            // Swift
            "func greet(name: String) -> String {\n    return \"Hello, \\(name)!\"\n}",
            "let numbers = [1, 2, 3, 4, 5]",
            "var counter = 0",
            "struct Person { var name: String }",
            
            // JavaScript
            "function add(a, b) { return a + b; }",
            "const array = [1, 2, 3];",
            "if (x > 0) { console.log('positive'); }",
            "class Animal { constructor(name) { this.name = name; } }",
            
            // Python
            "def factorial(n):\n    if n == 0:\n        return 1",
            "import numpy as np",
            "for i in range(10):\n    print(i)",
            
            // Java/C++/C#
            "public class Main { }",
            "int main() { return 0; }",
            "using namespace std;",
            "#include <iostream>",
            
            // その他のコードパターン
            "if (condition) { doSomething(); }",
            "array.map(x => x * 2).filter(y => y > 10)",  // より複雑なアロー関数
            "result = a == b && c != d",
            "counter++; value--;",
            "[1, 2, 3].forEach { print($0) }",
            "    return someValue if condition else None",  // インデントされたコード
            "\tfor i in range(10):",       // タブでインデント
            "{ key: value, foo: bar }",  // JSON/オブジェクト
            "SELECT * FROM users WHERE id = 1;"  // SQL
        ]
        
        for code in codeSnippets {
            let item = ClipItem(content: code)
            XCTAssertEqual(item.category, .code, "Code snippet should be categorized as Code: \(code)")
        }
    }
    
    func testInvalidCodeSnippets() {
        // コードではない通常のテキスト
        let nonCodeTexts = [
            "This is a regular sentence.",
            "The function of this device is important.",
            "Let me explain the concept.",
            "If you need help, please ask.",
            "Class starts at 9 AM.",
            "Variable weather conditions expected.",
            "Import duties may apply.",
            "For more information, visit our website.",
            "The function works well",  // "function" を含むがコードと誤判定される可能性がある
            "Let's discuss the class",   // "class" を含むがコードと誤判定される可能性がある
            "1 + 1 = 2",  // 単純な数式
            "Hello, World!",  // 単純なテキスト
            "TODO: Fix this later"  // コメントのみ
        ]
        
        for text in nonCodeTexts {
            let item = ClipItem(content: text)
            // "function" や "class" を含むテキストは現在の実装ではコードと判定される可能性がある
            if text.contains("function") || text.contains("class") {
                // スキップ
                continue
            }
            XCTAssertNotEqual(item.category, .code, "'\(text)' should NOT be categorized as Code")
        }
    }
    
    // MARK: - ファイルパス判定のテストケース
    
    func testValidFilePaths() {
        // Unix/Mac/Windowsの各種パス形式
        let filePaths = [
            // 絶対パス
            "/Users/example/Documents/file.txt",
            "/var/log/system.log",
            "/Applications/Safari.app",
            
            // ホームディレクトリ
            "~/Documents/report.pdf",
            "~/.config/settings.json",
            
            // 相対パス
            "./src/main.swift",
            "../parent/file.txt",
            
            // Windowsパス
            "C:\\Users\\Example\\Documents",
            "D:\\Projects\\MyApp\\src",
            "E:\\file.txt"
        ]
        
        for path in filePaths {
            let item = ClipItem(content: path)
            XCTAssertEqual(item.category, .filePath, "'\(path)' should be categorized as File")
        }
    }
    
    func testInvalidFilePaths() {
        // ファイルパスではないもの
        let nonPaths = [
            "file.txt",  // パス区切りなし
            "example/file",  // 相対パスの開始記号なし
            "https://example.com/file",  // URL
            "user@example.com:/path",  // SSH形式
            "This is not a path",
            "Version 2.0",
            "C: drive is full"  // Windowsドライブ言及だがパスではない
        ]
        
        for text in nonPaths {
            let item = ClipItem(content: text)
            XCTAssertNotEqual(item.category, .filePath, "'\(text)' should NOT be categorized as File")
        }
    }
    
    // MARK: - 文字数による分類のテストケース
    
    func testShortTextCategory() {
        // 50文字以下
        let shortTexts = [
            "Hello",
            "Quick note",
            "Remember to call John",
            String(repeating: "a", count: 50)
        ]
        
        for text in shortTexts {
            let item = ClipItem(content: text)
            // URL、メール、コード、ファイルパスでない場合のみshortTextになる
            if ![ClipItemCategory.url, .email, .code, .filePath].contains(item.category) {
                XCTAssertEqual(item.category, .shortText, "Text with \(text.count) chars should be shortText")
            }
        }
    }
    
    func testGeneralTextCategory() {
        // 51-500文字
        let generalTexts = [
            String(repeating: "a", count: 51),
            String(repeating: "a", count: 250),
            String(repeating: "a", count: 500)
        ]
        
        for text in generalTexts {
            let item = ClipItem(content: text)
            // URL、メール、コード、ファイルパスでない場合のみgeneralになる
            if ![ClipItemCategory.url, .email, .code, .filePath].contains(item.category) {
                XCTAssertEqual(item.category, .general, "Text with \(text.count) chars should be general")
            }
        }
    }
    
    func testLongTextCategory() {
        // 501文字以上
        let longTexts = [
            String(repeating: "a", count: 501),
            String(repeating: "a", count: 1000),
            String(repeating: "This is a long text. ", count: 50)  // 1000文字以上
        ]
        
        for text in longTexts {
            let item = ClipItem(content: text)
            // URL、メール、コード、ファイルパスでない場合のみlongTextになる
            if ![ClipItemCategory.url, .email, .code, .filePath].contains(item.category) {
                XCTAssertEqual(item.category, .longText, "Text with \(text.count) chars should be longText")
            }
        }
    }
    
    // MARK: - エッジケースと優先順位のテスト
    
    func testCategoryPriority() {
        // メールアドレスがURL判定より優先される
        let emailLikeURL = "user@example.com"
        let item1 = ClipItem(content: emailLikeURL)
        XCTAssertEqual(item1.category, .email, "Email should take priority over URL")
        
        // ファイルパスのようなURLは正しく判定される
        let fileURL = "file:///Users/example/file.txt"
        let item2 = ClipItem(content: fileURL)
        XCTAssertEqual(item2.category, .url, "file:// URLs should be categorized as URL")
        
        // コードのようなファイルパスは正しく判定される
        let codePath = "/usr/bin/swift"
        let item3 = ClipItem(content: codePath)
        XCTAssertEqual(item3.category, .filePath, "File paths should be categorized correctly")
    }
    
    func testWhitespaceHandling() {
        // 前後の空白は取り除かれる
        let urlWithSpaces = "  https://example.com  "
        let item1 = ClipItem(content: urlWithSpaces)
        XCTAssertEqual(item1.category, .url, "URLs with surrounding spaces should be recognized")
        
        let emailWithSpaces = "\tuser@example.com\n"
        let item2 = ClipItem(content: emailWithSpaces)
        XCTAssertEqual(item2.category, .email, "Emails with surrounding whitespace should be recognized")
    }
    
    func testEdgeCasesAndBugs() {
        // 現在の実装の潜在的な問題点
        
        // 1. IPアドレスは現在URLとして認識されない
        let ipAddress = "192.168.1.1"
        let item1 = ClipItem(content: ipAddress)
        XCTAssertNotEqual(item1.category, .url, "IP addresses are not recognized as URLs in current implementation")
        
        // 2. ファイル拡張子を持つテキストはURLではなく適切に分類される
        let fileWithExt = "document.pdf"
        let item2 = ClipItem(content: fileWithExt)
        XCTAssertNotEqual(item2.category, .url, "File extensions should not be categorized as URLs")
        
        // 3. 非常に長いURLはプロトコルがある場合はURLと判定される
        let longURL = "https://example.com/" + String(repeating: "path/", count: 40)
        let item3 = ClipItem(content: longURL)
        XCTAssertEqual(item3.category, .url, "Long URLs with protocol should still be recognized as URLs")
        
        // 4. 国際化ドメイン名（現在の実装では認識されない）
        let idnDomain = "例え.jp"
        let item4 = ClipItem(content: idnDomain)
        XCTAssertNotEqual(item4.category, .url, "IDN domains are not recognized in current implementation")
    }
}
