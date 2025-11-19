import SwiftUI
import AppKit

struct HoverTrackingView<Content: View>: View {
    let content: Content
    let onHover: (Bool, NSView) -> Void
    let isScrollLocked: Bool

    var body: some View {
        content
            .overlay(
                TrackingOverlay(onHover: onHover, isScrollLocked: isScrollLocked)
                    .allowsHitTesting(false)
            )
    }
}

private struct TrackingOverlay: NSViewRepresentable {
    let onHover: (Bool, NSView) -> Void
    let isScrollLocked: Bool

    func makeNSView(context: Context) -> TrackingOverlayView {
        let view = TrackingOverlayView(onHover: onHover)
        view.isScrollLocked = isScrollLocked
        return view
    }

    func updateNSView(_ nsView: TrackingOverlayView, context: Context) {
        nsView.onHover = onHover
        nsView.isScrollLocked = isScrollLocked
        nsView.refreshTrackingArea()
    }
}

final class TrackingOverlayView: NSView {
    var onHover: (Bool, NSView) -> Void
    private(set) var trackingArea: NSTrackingArea?
    private var cachedTrackingBounds: CGRect?
    var isScrollLocked: Bool = false {
        didSet {
            if oldValue && !isScrollLocked {
                // Scrollが解除され、マウスがまだ内部ならホバーを再送
                if isMouseInside {
                    onHover(true, self)
                }
            } else if !oldValue && isScrollLocked {
                // ロック時はここでは何もしない（List側でクリア）
            }
        }
    }
    private var isMouseInside = false

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
        let currentBounds = bounds
        if let cached = cachedTrackingBounds,
           cached.equalTo(currentBounds),
           trackingArea != nil {
            return
        }

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInKeyWindow,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: currentBounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        cachedTrackingBounds = currentBounds
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        if !isScrollLocked {
            onHover(true, self)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        if !isScrollLocked {
            onHover(false, self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func removeFromSuperview() {
        if !isScrollLocked {
            onHover(false, self)
        }
        super.removeFromSuperview()
    }
}
