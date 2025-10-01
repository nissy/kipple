import SwiftUI
import AppKit

struct HoverTrackingView<Content: View>: NSViewRepresentable {
    let content: Content
    let onHover: (Bool, NSView) -> Void

    func makeNSView(context: Context) -> TrackingView<Content> {
        TrackingView(rootView: content, onHover: onHover)
    }

    func updateNSView(_ nsView: TrackingView<Content>, context: Context) {
        nsView.hosting.rootView = content
    }
}

final class TrackingView<Content: View>: NSView {
    let hosting: NSHostingView<Content>
    private var onHover: (Bool, NSView) -> Void
    private var trackingArea: NSTrackingArea?

    init(rootView: Content, onHover: @escaping (Bool, NSView) -> Void) {
        self.hosting = NSHostingView(rootView: rootView)
        self.onHover = onHover
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateTrackingArea()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
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
}
