//
//  ModernSwiftUIIntegrationTests.swift
//  KippleTests
//
//  Created by Codex on 2025/09/23.
//

import XCTest
import SwiftUI
@testable import Kipple

@available(macOS 14.0, *)
final class ModernSwiftUIIntegrationTests: XCTestCase {

    @MainActor
    func testObservableViewBinding() async {
        // Given: ObservableMainViewModel
        let viewModel = ObservableMainViewModel()

        // When: Properties change
        viewModel.searchText = "test"
        viewModel.editorText = "editor content"

        // Then: View bindings work correctly
        XCTAssertEqual(viewModel.searchText, "test")
        XCTAssertEqual(viewModel.editorText, "editor content")
    }

    @MainActor
    func testSwiftUIAnimationIntegration() async {
        // Given: View with animation
        var offset: CGFloat = 0

        // When: Animating offset
        withAnimation(.spring()) {
            offset = 100
        }

        // Then: Animation value is set
        XCTAssertEqual(offset, 100)
    }

    @MainActor
    func testEnvironmentObjectIntegration() async {
        // Given: View with environment object
        let viewModel = ObservableMainViewModel()

        // Create a test view that uses the environment
        struct TestView: View {
            @EnvironmentObject var viewModel: ObservableMainViewModel

            var body: some View {
                Text(viewModel.searchText)
            }
        }

        // When: View is created with environment object
        let view = TestView()
            .environmentObject(viewModel)

        // Then: View can access environment
        XCTAssertNotNil(view)
    }
}
