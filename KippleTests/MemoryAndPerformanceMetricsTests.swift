//
//  MemoryAndPerformanceMetricsTests.swift
//  KippleTests
//
//  Focused metrics tests for memory/performance-sensitive paths.
//

import XCTest
@testable import Kipple

final class MemoryAndPerformanceMetricsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Use generous limits to avoid cleanup interfering with metrics
        UserDefaults.standard.set(1_000, forKey: "maxHistoryItems")
        UserDefaults.standard.set(1_000, forKey: "maxPinnedItems")
        UserDefaults.standard.set(128 * 1024, forKey: "maxClipboardBytes") // 128KB for tests
        ClipboardService.shared.history = []
    }

    override func tearDown() {
        ClipboardService.shared.history = []
        super.tearDown()
    }

    // MARK: - Clipboard history metrics

    func testAddToHistory_MemoryAndTimeMetrics() {
        let svc = ClipboardService.shared
        let appInfo = ClipboardService.AppInfo(appName: "TestApp", windowTitle: nil, bundleId: "com.example", pid: 0)

        // Measure memory+time while adding a few hundred short items via the real path
        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()]) {
            for i in 0..<300 {
                let content = "Item #\(i)"
                svc.addToHistoryWithAppInfo(content, appInfo: appInfo, isFromEditor: false)
            }
            // Allow async main-actor updates to settle
            let exp = expectation(description: "settle")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
            waitForExpectations(timeout: 1.0)
        }

        // Sanity: we inserted items (upper bounded by configured max)
        XCTAssertFalse(svc.history.isEmpty)
    }

    // MARK: - Classifier cache metrics

    func testCategoryClassifierCache_MemoryAndTime() {
        let classifier = CategoryClassifier.shared
        let long = String(repeating: "A", count: 2_000) // triggers long-text fast path

        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()]) {
            for i in 0..<500 {
                _ = classifier.classify(content: "\(i)-\(long)", isFromEditor: false)
            }
        }
    }

    // MARK: - Timer lifecycle (no accumulation)

    @MainActor
    func testAutoClearTimer_RestartMetrics() throws {
        // Record memory/time around repeated restarts to detect regressions over time in reports
        AppSettings.shared.enableAutoClear = true
        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()]) {
            for _ in 0..<5 {
                ClipboardService.shared.startAutoClearTimerIfNeeded()
                // short delay to emulate normal ticks
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                ClipboardService.shared.restartAutoClearTimer()
            }
            ClipboardService.shared.stopAutoClearTimer()
        }
        XCTAssertNil(ClipboardService.shared.autoClearTimer)
    }
}

// Simple weak box to check deallocation without retaining
private final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T? = nil) { self.value = value }
}
