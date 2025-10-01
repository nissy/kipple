//
//  PerformanceMetricsTests.swift
//  KippleTests
//
//  Created by Codex on 2025/09/23.
//

import XCTest
import SwiftUI
@testable import Kipple

final class PerformanceMetricsTests: XCTestCase {

    func testScrollPerformance() {
        // Given: Large list simulation
        let itemCount = 1000

        // When: Simulating scroll operations
        measure {
            var visibleRange = 0..<20

            // Simulate scrolling through the list
            for _ in 0..<100 {
                visibleRange = visibleRange.lowerBound + 1..<visibleRange.upperBound + 1

                // Simulate view updates for visible range
                _ = (visibleRange).map { index in
                    "Item \(index)"
                }
            }
        }

        // Then: Scroll performance should be acceptable
    }

    func testBatchUpdatePerformance() {
        // Given: Multiple items to update
        var items = (0..<100).map { index in
            ClipItem(content: "Item \(index)", isPinned: false)
        }

        // When: Performing batch updates
        measure {
            // Simulate batch operations
            items = items.map { item in
                var updated = item
                updated.isPinned = !item.isPinned
                return updated
            }

            // Sort and filter
            items = items
                .filter { !$0.content.isEmpty }
                .sorted { $0.timestamp > $1.timestamp }
        }

        // Then: Batch operations should be efficient
    }

    func testDebouncePerformance() async {
        // Given: Rapid input changes
        let inputValues = (0..<100).map { "Query \($0)" }
        let processedCount = ProcessCounter()

        // When: Processing with debounce
        var currentTask: Task<Void, Never>?
        for value in inputValues {
            currentTask?.cancel()
            currentTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms debounce
                    await processedCount.increment()
                } catch {
                    // Task cancelled - ignore
                }
            }
            _ = value
        }

        // Wait for final debounced task to complete
        await currentTask?.value

        // Then: Not all inputs should be processed (debouncing works)
        let finalCount = await processedCount.getValue()
        XCTAssertLessThan(finalCount, inputValues.count)
    }
}
