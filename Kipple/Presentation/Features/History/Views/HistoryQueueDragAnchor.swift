import AppKit
import SwiftUI

struct HistoryQueueDragAnchor: NSViewRepresentable {
    let controller: HistoryQueueDragController
    var itemID: UUID?
    var actions: QueueReorderActions?
    var visibleIDs: [UUID] = []

    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.controller = controller
        view.itemID = itemID
        if let itemID {
            controller.register(view, for: itemID)
        } else {
            controller.surface = view
            controller.actions = actions
            controller.visibleIDs = visibleIDs
        }
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: ()) {
        if let itemID = view.itemID {
            view.controller?.unregister(view, for: itemID)
        } else {
            view.controller?.cancel()
            view.controller?.surface = nil
        }
    }

    final class AnchorView: NSView {
        weak var controller: HistoryQueueDragController?
        var itemID: UUID?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
