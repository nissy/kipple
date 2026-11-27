import AppKit
import SwiftUI

enum DesktopNoteColor: String, Codable {
    case none = "No Note Color"
    case black = "HTML Black Note Color"
    case gray = "HTML Gray Note Color"
    case silver = "HTML Silver Note Color"
    case white = "HTML White Note Color"
    case maroon = "HTML Maroon Note Color"
    case red = "HTML Red Note Color"
    case olive = "HTML Olive Note Color"
    case yellow = "HTML Yellow Note Color"
    case green = "HTML Green Note Color"
    case lime = "HTML Lime Note Color"
    case teal = "HTML Teal Note Color"
    case aqua = "HTML Aqua Note Color"
    case navy = "HTML Navy Note Color"
    case blue = "HTML Blue Note Color"
    case purple = "HTML Purple Note Color"
    case fuchsia = "HTML Fuchsia Note Color"

    // These identifiers and colors are used by notes saved before the HTML palette.
    case legacyYellow = "Yellow Note Color"
    case legacyOrange = "Orange Note Color"
    case legacyBlue = "Blue Note Color"
    case legacyGreen = "Green Note Color"
    case legacyPink = "Pink Note Color"

    static let palette: [Self] = [
        .black, .gray, .silver, .white, .maroon, .red, .olive, .yellow,
        .green, .lime, .teal, .aqua, .navy, .blue, .purple, .fuchsia
    ]

    var fill: NSColor? {
        switch self {
        case .none: nil
        case .black: Self.sRGB(0x000000)
        case .gray: Self.sRGB(0x808080)
        case .silver: Self.sRGB(0xC0C0C0)
        case .white: Self.sRGB(0xFFFFFF)
        case .maroon: Self.sRGB(0x800000)
        case .red: Self.sRGB(0xFF0000)
        case .olive: Self.sRGB(0x808000)
        case .yellow: Self.sRGB(0xFFFF00)
        case .green: Self.sRGB(0x008000)
        case .lime: Self.sRGB(0x00FF00)
        case .teal: Self.sRGB(0x008080)
        case .aqua: Self.sRGB(0x00FFFF)
        case .navy: Self.sRGB(0x000080)
        case .blue: Self.sRGB(0x0000FF)
        case .purple: Self.sRGB(0x800080)
        case .fuchsia: Self.sRGB(0xFF00FF)
        case .legacyYellow: .systemYellow
        case .legacyOrange: .systemOrange
        case .legacyBlue: .systemBlue
        case .legacyGreen: .systemGreen
        case .legacyPink: .systemPink
        }
    }

    private static func sRGB(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

@MainActor
final class DesktopNoteContentController: NSViewController {
    let hostingController: NSHostingController<DesktopNoteContent>
    var selectionMayExist = false
    private(set) lazy var remoteImagesButton = makeButton(
        "photo", labelKey: "Load External Images", target: self, action: #selector(loadRemoteImages)
    )

    init(rootView: DesktopNoteContent) {
        hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []
        hostingController.safeAreaRegions = []
        super.init(nibName: nil, bundle: nil)
        addChild(hostingController)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(_ content: DesktopNoteContent) {
        hostingController.rootView = content
        remoteImagesButton.isHidden = !content.offersRemoteImages
    }

    var previewScrollProgress: CGFloat {
        guard let clip = scrollViews(in: hostingController.view).first?.contentView else { return 0 }
        let document = clip.documentRect
        let travel = document.height - clip.bounds.height
        guard travel > 0 else { return 0 }
        return min(1, max(0, (clip.bounds.minY - document.minY) / travel))
    }

    @objc private func loadRemoteImages() {
        var content = hostingController.rootView
        guard content.offersRemoteImages else { return }
        content.allowsRemoteImages = true
        setContent(content)
        (view.window as? DesktopNotePanel)?.didLoadRemoteImages()
    }

    func clearSelection() {
        guard let window = view.window, selectionMayExist || window.firstResponder !== window else { return }
        let scrollOrigins = scrollViews(in: view).map(\.contentView.bounds.origin)
        selectionMayExist = false
        window.makeFirstResponder(nil)
        // A new text view identity clears SwiftUI and Textual selection state.
        hostingController.rootView.selectionRevision += 1
        let revision = hostingController.rootView.selectionRevision
        DispatchQueue.main.async { [weak self] in
            guard let self, hostingController.rootView.selectionRevision == revision else { return }
            view.layoutSubtreeIfNeeded()
            for (scrollView, origin) in zip(scrollViews(in: view), scrollOrigins) {
                let clipView = scrollView.contentView
                clipView.scroll(to: origin)
                scrollView.reflectScrolledClipView(clipView)
            }
        }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let descendants = view.subviews.flatMap(scrollViews(in:))
        return (view as? NSScrollView).map { [$0] + descendants } ?? descendants
    }

    func makeButton(
        _ symbol: String, labelKey: String, titleKey: String? = nil, target: AnyObject, action: Selector
    ) -> NSButton {
        let button = NSButton(frame: .zero)
        let label = AppSettings.shared.localizedString(labelKey)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentTintColor = .secondaryLabelColor
        button.target = target
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        if let titleKey {
            button.title = AppSettings.shared.localizedString(titleKey)
            button.font = .systemFont(ofSize: 12)
        }
        NSLayoutConstraint.activate([
            titleKey == nil ? button.widthAnchor.constraint(equalToConstant: KippleButtonMetrics.compactIconSize)
                : button.widthAnchor.constraint(greaterThanOrEqualToConstant: KippleButtonMetrics.compactIconSize),
            button.heightAnchor.constraint(equalToConstant: KippleButtonMetrics.compactIconSize)
        ])
        return button
    }

    func makeColorMenu(selected: DesktopNoteColor, target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for color in DesktopNoteColor.palette + [.none] {
            if color == .none { menu.addItem(.separator()) }
            let title = AppSettings.shared.localizedString(color.rawValue)
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = color.rawValue
            if let fill = color.fill {
                item.image = Self.colorSwatch(fill)
#if compiler(>=6.4)
                if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
#endif
            }
            item.state = color == selected ? .on : .off
        }
        return menu
    }

    private static func colorSwatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { bounds in
            let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            color.setFill()
            circle.fill()
            NSColor.labelColor.withAlphaComponent(0.30).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
    }

    override func loadView() {
        let container = DesktopNoteBackgroundView()
        container.wantsLayer = true
        container.layer?.cornerRadius = HistoryItemPreviewContent.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let content = hostingController.view
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
    }
}

private final class DesktopNoteBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(1).setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
