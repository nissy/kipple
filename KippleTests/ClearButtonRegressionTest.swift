//
//  ClearButtonRegressionTest.swift
//  KippleTests
//
//  Created by Kipple on 2025/01/07.
//

import XCTest
import SwiftUI
@testable import Kipple

@MainActor
class ClearButtonRegressionTest: XCTestCase {
    var viewModel: MainViewModel!
    var mockClipboardService: MockClipboardService!
    
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "lastEditorText")
        mockClipboardService = MockClipboardService()
        viewModel = MainViewModel(clipboardService: mockClipboardService)
    }
    
    override func tearDown() {
        viewModel = nil
        mockClipboardService = nil
        UserDefaults.standard.removeObject(forKey: "lastEditorText")
        super.tearDown()
    }
    
    func testClearEditorWithAlphanumericText() {
        // Test case 1: Pure alphanumeric text
        viewModel.editorText = "test123"
        viewModel.clearEditor()
        XCTAssertEqual(viewModel.editorText, "", "Failed to clear alphanumeric text")
        
        // Test case 2: Mixed alphanumeric with spaces
        viewModel.editorText = "test 123 abc"
        viewModel.clearEditor()
        XCTAssertEqual(viewModel.editorText, "", "Failed to clear alphanumeric text with spaces")
        
        // Test case 3: Alphanumeric with special characters
        viewModel.editorText = "test@123#abc"
        viewModel.clearEditor()
        XCTAssertEqual(viewModel.editorText, "", "Failed to clear alphanumeric text with special characters")
        
        // Test case 4: Japanese text (should work)
        viewModel.editorText = "テスト123"
        viewModel.clearEditor()
        XCTAssertEqual(viewModel.editorText, "", "Failed to clear Japanese text")
        
        // Test case 5: Emojis and alphanumeric
        viewModel.editorText = "test123🎉"
        viewModel.clearEditor()
        XCTAssertEqual(viewModel.editorText, "", "Failed to clear text with emojis")
    }
    
    func testClearEditorPersistence() {
        let key = "lastEditorText"

        viewModel.editorText = "test123"
        let expectation = XCTestExpectation(description: "Wait for debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNil(UserDefaults.standard.string(forKey: key))

        viewModel.clearEditor()

        XCTAssertNil(UserDefaults.standard.string(forKey: key), "Live editor should not persist text")
        XCTAssertTrue(mockClipboardService.writeToClipboardOnlyCalled)
    }
    
    func testClearButtonBinding() {
        // Test the binding between Clear button and clearEditor method
        
        // Create a simple test view that mimics MainViewControlSection
        struct TestView: View {
            @ObservedObject var viewModel: MainViewModel
            @State var clearCalled = false
            
            var body: some View {
                Button("Clear") {
                    viewModel.clearEditor()
                    clearCalled = true
                }
            }
        }
        
        // Set initial text
        viewModel.editorText = "test123"
        
        // Simulate button press through the view model
        viewModel.clearEditor()
        
        // Verify text was cleared
        XCTAssertEqual(viewModel.editorText, "")
    }
}
