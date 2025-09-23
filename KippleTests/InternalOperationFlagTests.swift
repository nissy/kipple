//
//  InternalOperationFlagTests.swift
//  KippleTests
//
//  Tests for internal operation flag handling
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class InternalOperationFlagTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!
    
    override func setUp() async throws {
        try await super.setUp()
        
        service = ModernClipboardService.shared
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared
        
        // Clear any existing data
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        await service.flushPendingSaves()
    }
    
    override func tearDown() async throws {
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        
        service = nil
        adapter = nil
        
        try await super.tearDown()
    }
    
    func testExternalCopyAfterClearSystemClipboard() async throws {
        // Given: Start monitoring
        await service.startMonitoring()
        
        // Add initial items
        await service.copyToClipboard("Initial", fromEditor: false)
        await service.flushPendingSaves()
        
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        
        // When: Clear system clipboard
        await adapter.clearSystemClipboard()
        
        // Immediately copy something externally (simulate quick user action)
        // Small delay to ensure clear completes
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Simulate external copy
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("External Copy", forType: .string)
        
        // Wait for monitoring to detect the change
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Then: External copy should be added to history
        history = await service.getHistory()
        XCTAssertTrue(history.contains { $0.content == "External Copy" },
                     "External copy should be detected after clear clipboard")
        
        await service.stopMonitoring()
    }
    
    func testInternalOperationDoesNotBlockSubsequentExternal() async throws {
        // Given: Start monitoring
        await service.startMonitoring()
        
        // When: Perform internal operation (recopy)
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.flushPendingSaves()
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        var history = await service.getHistory()
        let item = history[1] // Item 1
        await service.recopyFromHistory(item)
        
        // Small delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // External copy
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("External After Recopy", forType: .string)
        
        // Wait for detection
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Then: External copy should be detected
        history = await service.getHistory()
        XCTAssertTrue(history.contains { $0.content == "External After Recopy" },
                     "External copy after recopy should be detected")
        
        await service.stopMonitoring()
    }
    
    func testRapidExternalCopiesAfterInternalOperation() async throws {
        // Given: Start monitoring
        await service.startMonitoring()
        
        await service.copyToClipboard("Base", fromEditor: false)
        await service.flushPendingSaves()
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // When: Clear clipboard then rapid external copies
        await adapter.clearSystemClipboard()
        
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Simulate rapid external copies
        for i in 1...3 {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("Rapid \(i)", forType: .string)
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds between copies
        }
        
        // Then: All external copies should be detected
        let history = await service.getHistory()
        XCTAssertTrue(history.contains { $0.content == "Rapid 3" },
                     "Last rapid copy should be detected")
        
        // At least the last one should be there
        // (intermediate ones might be missed due to polling interval)
        
        await service.stopMonitoring()
    }
}
