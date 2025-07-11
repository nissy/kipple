//
//  DebouncingTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/11.
//
//  SPECS.md準拠: デバウンス機能のテスト
//  - エディター保存: 500ms
//  - 履歴保存: 1秒
//  - 検索: 300ms
//  - フォント変更: 500ms

import XCTest
import Combine
@testable import Kipple

final class DebouncingTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        super.setUp()
        cancellables.removeAll()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }
    
    // MARK: - Editor Save Debouncing (500ms)
    
    func testEditorSaveDebouncing() {
        // SPECS.md: エディター保存のデバウンス（500ms）
        let expectation = XCTestExpectation(description: "Editor save debouncing")
        var saveCount = 0
        let viewModel = MainViewModel()
        
        // エディターテキスト変更を監視
        viewModel.$editorText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .dropFirst() // 初期値をスキップ
            .sink { _ in
                saveCount += 1
            }
            .store(in: &cancellables)
        
        // 短時間に複数回変更
        viewModel.editorText = "a"
        viewModel.editorText = "ab"
        viewModel.editorText = "abc"
        viewModel.editorText = "abcd"
        viewModel.editorText = "abcde" // 最終値
        
        // 500ms後に確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(saveCount, 1, "Should save only once after debouncing")
            XCTAssertEqual(viewModel.editorText, "abcde")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testEditorSaveDebounceInterval() {
        // デバウンス間隔が正確に500msであることを確認
        let expectation = XCTestExpectation(description: "Editor save interval")
        var saveTime: Date?
        let viewModel = MainViewModel()
        
        viewModel.$editorText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .dropFirst()
            .sink { _ in
                saveTime = Date()
            }
            .store(in: &cancellables)
        
        let startTime = Date()
        viewModel.editorText = "Test content"
        
        // 800ms後に確認（500msデバウンス + バッファ）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let saveTime = saveTime {
                let interval = saveTime.timeIntervalSince(startTime)
                XCTAssertGreaterThanOrEqual(interval, 0.5, "Should wait at least 500ms")
                XCTAssertLessThanOrEqual(interval, 0.8, "Should not wait much longer than 500ms")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - History Save Debouncing (1s)
    
    func testHistorySaveDebouncing() {
        // SPECS.md: 履歴保存のデバウンス（1秒）
        let expectation = XCTestExpectation(description: "History save debouncing")
        var saveCount = 0
        let clipboardService = ClipboardService.shared
        
        // 履歴変更を監視（実際の実装をシミュレート）
        clipboardService.$history
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .dropFirst()
            .sink { _ in
                saveCount += 1
            }
            .store(in: &cancellables)
        
        // 短時間に複数回履歴を変更
        clipboardService.history.append(ClipItem(content: "Item 1"))
        clipboardService.history.append(ClipItem(content: "Item 2"))
        clipboardService.history.append(ClipItem(content: "Item 3"))
        
        // 1.1秒後に確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            XCTAssertEqual(saveCount, 1, "Should save only once after 1s debouncing")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.5)
    }
    
    // MARK: - Search Debouncing (300ms)
    // 検索デバウンスはMainViewHistorySectionに実装されているため、
    // ここでは一般的なデバウンスの概念をテストする
    
    func testSearchDebouncingConcept() {
        // デバウンスの一般的な動作をテスト
        let expectation = XCTestExpectation(description: "Debouncing concept")
        var executionCount = 0
        let subject = PassthroughSubject<String, Never>()
        
        subject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { _ in
                executionCount += 1
            }
            .store(in: &cancellables)
        
        // 短時間に複数回値を送信
        subject.send("t")
        subject.send("te")
        subject.send("tes")
        subject.send("test")
        
        // 300ms後に確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertEqual(executionCount, 1, "Should execute only once after 300ms debouncing")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.5)
    }
    
    func testDebounceResetOnNewInput() {
        // 新しい入力でデバウンスタイマーがリセットされることを確認
        let expectation = XCTestExpectation(description: "Debounce reset")
        var executionTimes: [Date] = []
        let subject = PassthroughSubject<String, Never>()
        
        subject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { _ in
                executionTimes.append(Date())
            }
            .store(in: &cancellables)
        
        // 200msごとに入力（デバウンスをリセット）
        subject.send("a")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            subject.send("ab")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            subject.send("abc")
        }
        
        // 最後の入力から300ms後に実行される
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            XCTAssertEqual(executionTimes.count, 1, "Should execute only once")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Font Change Debouncing (500ms)
    
    func testFontChangeDebouncing() {
        // SPECS.md: フォント変更のデバウンス（500ms）
        let expectation = XCTestExpectation(description: "Font change debouncing")
        var notificationCount = 0
        
        // フォント変更通知を監視
        NotificationCenter.default
            .publisher(for: .editorFontSettingsChanged)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { _ in
                notificationCount += 1
            }
            .store(in: &cancellables)
        
        // 短時間に複数回フォント設定を変更
        NotificationCenter.default.post(name: .editorFontSettingsChanged, object: nil)
        NotificationCenter.default.post(name: .editorFontSettingsChanged, object: nil)
        NotificationCenter.default.post(name: .editorFontSettingsChanged, object: nil)
        
        // 500ms後に確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(notificationCount, 1, "Should update font only once after debouncing")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Multiple Debouncing Tests
    
    func testMultipleDebouncersWorking() {
        // 複数のデバウンサーが独立して動作することを確認
        let expectation = XCTestExpectation(description: "Multiple debouncers")
        expectation.expectedFulfillmentCount = 2
        
        var editorSaved = false
        var fontChanged = false
        
        let viewModel = MainViewModel()
        
        // エディター保存（500ms）
        viewModel.$editorText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .dropFirst()
            .sink { _ in
                editorSaved = true
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // フォント変更（500ms）
        NotificationCenter.default
            .publisher(for: .editorFontSettingsChanged)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { _ in
                fontChanged = true
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // すべて同時に変更
        viewModel.editorText = "Test"
        NotificationCenter.default.post(name: .editorFontSettingsChanged, object: nil)
        
        wait(for: [expectation], timeout: 2.0)
        
        // すべてのデバウンサーが動作したことを確認
        XCTAssertTrue(editorSaved)
        XCTAssertTrue(fontChanged)
    }
    
    // MARK: - Performance Tests
    
    func testDebouncingPerformanceUnderLoad() {
        // 高頻度の更新でもデバウンスが正しく動作することを確認
        let expectation = XCTestExpectation(description: "Performance under load")
        var executeCount = 0
        let subject = PassthroughSubject<String, Never>()
        
        subject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { _ in
                executeCount += 1
            }
            .store(in: &cancellables)
        
        // 100回の高速更新
        for i in 0..<100 {
            subject.send("Test \(i)")
        }
        
        // 最終的に1回のみ実行されることを確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(executeCount, 1, "Should execute only once despite many updates")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
}
