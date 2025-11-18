import SwiftUI
import AppKit

struct HoverTrackingView<Content: View>: View {
    let content: Content
    let onHover: (Bool, NSView) -> Void

    var body: some View {
        content
            .overlay(
                TrackingOverlay(onHover: onHover)
                    .allowsHitTesting(false)
            )
    }
}

private struct TrackingOverlay: NSViewRepresentable {
    let onHover: (Bool, NSView) -> Void

    func makeNSView(context: Context) -> TrackingOverlayView {
        TrackingOverlayView(onHover: onHover)
    }

    func updateNSView(_ nsView: TrackingOverlayView, context: Context) {
        nsView.onHover = onHover
        nsView.refreshTrackingArea()
    }
}

private final class TrackingOverlayView: NSView {
    var onHover: (Bool, NSView) -> Void
    private var trackingArea: NSTrackingArea?

    init(onHover: @escaping (Bool, NSView) -> Void) {
        self.onHover = onHover
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        refreshTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    func refreshTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInKeyWindow,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover(true, self)
    }

    override func mouseExited(with event: NSEvent) {
        onHover(false, self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func removeFromSuperview() {
        onHover(false, self)
        super.removeFromSuperview()
    }
}
