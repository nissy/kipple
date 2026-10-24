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
    private var hoverNotificationID = 0
    var isScrollLocked: Bool = false {
        didSet {
            guard oldValue != isScrollLocked else { return }
            hoverNotificationID &+= 1
            if !isScrollLocked && isMouseInside {
                scheduleHoverNotification(true)
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
            scheduleHoverNotification(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        if !isScrollLocked {
            scheduleHoverNotification(false)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func removeFromSuperview() {
        isMouseInside = false
        hoverNotificationID &+= 1
        if !isScrollLocked {
            scheduleHoverNotification(false)
        }
        super.removeFromSuperview()
    }

    private func scheduleHoverNotification(_ hovering: Bool) {
        hoverNotificationID &+= 1
        let notificationID = hoverNotificationID
        // SwiftUI can update the scroll lock or remove this view during a view update.
        // Deliver only the latest hover state after that update has finished.
        DispatchQueue.main.async { [self] in
            guard notificationID == hoverNotificationID, !isScrollLocked else { return }
            onHover(hovering, self)
        }
    }
}
