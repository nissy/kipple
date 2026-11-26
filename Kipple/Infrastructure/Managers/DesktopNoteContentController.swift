import AppKit
import SwiftUI

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
            titleKey == nil ? button.widthAnchor.constraint(equalToConstant: 24)
                : button.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
        return button
    }

    func makeColorMenu(selected: DesktopNoteColor, target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for color in DesktopNoteColor.allCases {
            let title = AppSettings.shared.localizedString(color.rawValue)
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = color.rawValue
            item.state = color == selected ? .on : .off
        }
        return menu
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
