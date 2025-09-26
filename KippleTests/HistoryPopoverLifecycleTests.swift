import XCTest
import SwiftUI
import AppKit
@testable import Kipple

@MainActor
final class HistoryPopoverLifecycleTests: XCTestCase {

    func testDismissClearsPopoverAndHostingController() {
        var isPresented = true
        let binding = Binding(get: { isPresented }, set: { isPresented = $0 })
        let presenter = HoverPopoverPresenter(isPresented: binding, arrowEdge: .trailing) {
            Text("Popover")
        }

        let coordinator = presenter.makeCoordinator()
        coordinator.debugForcePresentation(
            isPresented: binding,
            arrowEdge: .trailing
        ) { AnyView(Text("First")) }

        var state = coordinator.debugState()
        XCTAssertTrue(state.hasPopover)
        XCTAssertTrue(state.hasHostingController)
        XCTAssertTrue(state.hasContentProvider)
        XCTAssertNotNil(coordinator.debugPopoverObject())

        coordinator.debugDismissPopover()

        state = coordinator.debugState()
        XCTAssertFalse(state.hasPopover)
        XCTAssertFalse(state.hasHostingController)
        XCTAssertFalse(state.hasContentProvider)
        XCTAssertFalse(isPresented)
    }

    func testPopoverReuseHostingControllerBetweenUpdates() {
        var isPresented = true
        let binding = Binding(get: { isPresented }, set: { isPresented = $0 })
        let presenter = HoverPopoverPresenter(isPresented: binding, arrowEdge: .leading) {
            Text("Initial")
        }

        let coordinator = presenter.makeCoordinator()
        coordinator.debugForcePresentation(
            isPresented: binding,
            arrowEdge: .leading
        ) { AnyView(Text("First")) }

        let firstController = coordinator.debugHostingControllerObject()
        XCTAssertNotNil(firstController)

        coordinator.debugForcePresentation(
            isPresented: binding,
            arrowEdge: .leading
        ) { AnyView(Text("Second")) }

        let secondController = coordinator.debugHostingControllerObject()
        XCTAssertTrue(coordinator.debugState().hasPopover)
        XCTAssertTrue(firstController === secondController)

        coordinator.popoverDidClose(Notification(name: NSPopover.willCloseNotification))
        XCTAssertFalse(coordinator.debugState().hasPopover)
        XCTAssertNil(coordinator.debugHostingControllerObject())

        XCTAssertFalse(isPresented)
    }
}
