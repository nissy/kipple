//
//  RecopyPerformanceTests.swift
//  KippleTests
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class RecopyPerformanceTests: XCTestCase {
    private struct MeasurementStats {
        let average: Double
        let min: Double
        let max: Double
    }

    private var service: ModernClipboardService!
    private var repository: MockClipboardRepository!
    private var sampleItems: [ClipItem] = []

    override func setUp() async throws {
        try await super.setUp()
        service = ModernClipboardService.shared
        repository = MockClipboardRepository()

        await service.resetForTesting()

        sampleItems = Self.makeSampleItems(count: 320)
        await repository.configure(items: sampleItems, loadDelay: 0)
        await service.useTestingRepository(repository)
        await service.flushPendingSaves()
    }

    override func tearDown() async throws {
        await service.resetForTesting()
        service = nil
        repository = nil
        sampleItems = []
        try await super.tearDown()
    }

    func testRecopyFromHistoryPerformance() async throws {
        let history = await service.getHistory()
        let targets = Array(history.suffix(80).reversed())

        guard targets.count >= 2 else {
            XCTFail("Not enough targets for measurement")
            return
        }

        let stats = await measureAverage(items: targets) { [self] item in
            await self.service.recopyFromHistory(item)
        }

        await service.flushPendingSaves()
        recordMetrics(named: "recopyFromHistory", stats: stats)
    }

    func testSelectHistoryItemPerformance() async throws {
        let mockService = MockClipboardService()
        mockService.history = sampleItems

        let viewModel = MainViewModel(clipboardService: mockService, pageSize: 320)
        viewModel.loadHistory()

        let targets = Array(mockService.history.suffix(80).reversed())

        guard targets.count >= 2 else {
            XCTFail("Not enough targets for measurement")
            return
        }

        let stats = measureAverageSync(items: targets) { item in
            viewModel.selectHistoryItem(item)
        }

        recordMetrics(named: "selectHistoryItem", stats: stats)
    }

    private func recordMetrics(named name: String, stats: MeasurementStats) {
        let message = String(
            format: "%@ avg=%.3fms min=%.3fms max=%.3fms",
            name,
            stats.average * 1_000,
            stats.min * 1_000,
            stats.max * 1_000
        )

        XCTContext.runActivity(named: "Performance \(name)") { activity in
            activity.add(XCTAttachment(string: message))
        }
    }

    private static func makeSampleItems(count: Int) -> [ClipItem] {
        let payload = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", count: 400)
        let now = Date()
        return (0..<count).map { index -> ClipItem in
            var item = ClipItem(content: payload + " #\(index)")
            item.timestamp = now.addingTimeInterval(-Double(index))
            return item
        }
    }

    private func measureAverage(
        items: [ClipItem],
        operation: @escaping (ClipItem) async -> Void
    ) async -> MeasurementStats {
        var durations: [Double] = []
        durations.reserveCapacity(items.count)

        for (offset, item) in items.enumerated() {
            let start = CFAbsoluteTimeGetCurrent()
            await operation(item)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            durations.append(elapsed)

            if offset == 0 {
                durations.removeAll()
            }
        }

        return summarize(durations: durations)
    }

    private func measureAverageSync(
        items: [ClipItem],
        operation: (ClipItem) -> Void
    ) -> MeasurementStats {
        var durations: [Double] = []
        durations.reserveCapacity(items.count)

        for (offset, item) in items.enumerated() {
            let start = CFAbsoluteTimeGetCurrent()
            operation(item)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            durations.append(elapsed)

            if offset == 0 {
                durations.removeAll()
            }
        }

        return summarize(durations: durations)
    }

    private func summarize(durations: [Double]) -> MeasurementStats {
        guard !durations.isEmpty else { return MeasurementStats(average: 0, min: 0, max: 0) }
        let total = durations.reduce(0, +)
        let average = total / Double(durations.count)
        let minValue = durations.min() ?? 0
        let maxValue = durations.max() ?? 0
        return MeasurementStats(average: average, min: minValue, max: maxValue)
    }
}
