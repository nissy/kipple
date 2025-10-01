import XCTest
import AppKit
@testable import Kipple

@MainActor
final class SettingsToolbarControllerTests: XCTestCase {
    func testToolbarSelectionUpdatesViewModelSequentially() {
        let viewModel = SettingsViewModel()
        let controller = SettingsToolbarController(viewModel: viewModel)
        
        controller.toolbar(NSToolbar(identifier: "test"), didSelect: SettingsViewModel.Tab.editor.toolbarIdentifier)
        XCTAssertEqual(viewModel.selectedTab, .editor)

        controller.toolbar(NSToolbar(identifier: "test"), didSelect: SettingsViewModel.Tab.clipboard.toolbarIdentifier)
        XCTAssertEqual(viewModel.selectedTab, .clipboard)
    }
}
