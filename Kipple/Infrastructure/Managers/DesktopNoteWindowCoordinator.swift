import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class DesktopNoteWindowCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DesktopNoteWindowCoordinator()

    @Published private var notes: [UUID: DesktopNotePanel] = [:]
    private let adapter: ModernClipboardServiceAdapter
    private var historyObservation: AnyCancellable?
    private var transparencyObservation: AnyCancellable?

    init(adapter: ModernClipboardServiceAdapter = .shared) {
        self.adapter = adapter
        super.init()
        historyObservation = adapter.$history.sink { [weak self] history in
            self?.updateOpenNotes(from: history)
        }
        let settings = AppSettings.shared
        transparencyObservation = settings.objectWillChange
            .receive(on: RunLoop.main)
            .map { settings.desktopNoteTransparency }
            .removeDuplicates()
            .sink { [weak self] value in
                self?.notes.values.forEach { $0.applyTransparency(value) }
            }
    }

    func isPosted(_ id: UUID) -> Bool {
        notes[id] != nil
    }

    func toggle(_ item: ClipItem, on screen: NSScreen?) {
        if let note = notes[item.id] {
            note.performClose(nil)
            return
        }
        guard let screen = screen ?? NSScreen.main else { return }

        let itemID = item.id
        let note = DesktopNotePanel(
            item: item,
            screenFrame: screen.visibleFrame,
            onSave: { [adapter] text in
                try await adapter.updateDetails(itemID: itemID, title: nil, content: text, categoryChanges: [:])
            },
            onChangeCategory: { [adapter] change in
                try await adapter.updateCategories(itemID: itemID, change: change)
            }
        )
        note.delegate = self
        note.setFrameOrigin(initialOrigin(for: note.frame.size, in: screen.visibleFrame))
        notes[item.id] = note
        note.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let note = notification.object as? DesktopNotePanel,
              let id = notes.first(where: { $0.value === note })?.key else { return }
        notes.removeValue(forKey: id)
    }

    private func updateOpenNotes(from history: [ClipItem]) {
        guard !notes.isEmpty else { return }
        for item in history {
            notes[item.id]?.update(from: item)
        }
    }

    private func initialOrigin(for size: NSSize, in frame: NSRect) -> NSPoint {
        let margin: CGFloat = 24
        let occupied = notes.values.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        let positions = (0..<8).map { index in
            let offset = margin * CGFloat(index + 1)
            return NSPoint(
                x: max(frame.minX, min(frame.minX + offset, frame.maxX - size.width)),
                y: max(frame.minY + size.height, frame.maxY - offset)
            )
        }
        let topLeft = positions.first { !occupied.contains($0) } ?? positions[0]
        return NSPoint(x: topLeft.x, y: topLeft.y - size.height)
    }
}

final class DesktopNotePanel: NSPanel {
    private static let controlsHeight: CGFloat = 32
    private let glassController: GlassWindowContentController<DesktopNoteContent>
    private let colorStrip = NSView()
    private let initialScreenFrame: NSRect
    private let onSave: ((String) async throws -> Void)?
    private let onChangeCategory: ((ClipCategoryChange) async throws -> Void)?
    private var categoryControl: NSHostingView<DesktopNoteCategoryMenu>?
    private var controls: [NSView] = []
    private var selectedColor = DesktopNoteColor.none
    private var dragOffset: NSPoint?
    private var editor: DesktopNoteEditor?
    private var isSaving = false
    private var closeAfterSave = false

    override var canBecomeKey: Bool { true }

    init(
        item: ClipItem,
        screenFrame: NSRect,
        onSave: ((String) async throws -> Void)? = nil,
        onChangeCategory: ((ClipCategoryChange) async throws -> Void)? = nil
    ) {
        let content = Self.makeContent(for: item)
        let size = Self.contentSize(for: content, screenFrame: screenFrame)
        initialScreenFrame = screenFrame
        self.onSave = onSave
        self.onChangeCategory = onChangeCategory
        glassController = GlassWindowContentController(
            rootView: content,
            cornerRadius: HistoryItemPreviewContent.cornerRadius
        )
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        // Stay above Finder's desktop icons and below regular application windows.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        title = HistoryItemPreviewContent.nonempty(item.title) ?? ""
        titleVisibility = .hidden
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        contentViewController = glassController
        applyTransparency(AppSettings.shared.desktopNoteTransparency)
        setContentSize(size)
        installColorStrip(in: glassController.view)
        installControls(in: glassController.view, for: item)
    }

    func applyTransparency(_ value: Double) {
        glassController.glassOpacity = 1 - value
    }

    func update(from item: ClipItem) {
        if let categoryControl, categoryControl.rootView.item.categoryIDs != item.categoryIDs {
            categoryControl.rootView.item = item
        }
        let hostingController = glassController.hostingController
        let previous = hostingController.rootView.preview.item
        guard item.title != previous.title || item.content != previous.content else { return }

        var content = Self.makeContent(for: item)
        content.preview.showsBody = editor == nil
        title = HistoryItemPreviewContent.nonempty(item.title) ?? ""
        hostingController.rootView = content
        if editor == nil { resize(to: Self.contentSize(for: content, screenFrame: availableFrame)) }
    }

    private var availableFrame: NSRect { screen?.visibleFrame ?? initialScreenFrame }

    private func resize(to size: NSSize) {
        guard size != frame.size else { return }
        let origin = NSPoint(
            x: min(frame.minX, availableFrame.maxX - size.width),
            y: max(frame.maxY - size.height, availableFrame.minY)
        )
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragOffset = nil
            guard isNoteBody(at: event.locationInWindow) else { break }
            if event.clickCount == 2, editor == nil, onSave != nil {
                beginEditing(at: convertPoint(toScreen: event.locationInWindow))
            } else {
                dragOffset = event.locationInWindow
            }
            return
        case .leftMouseDragged:
            if let dragOffset {
                let pointer = convertPoint(toScreen: event.locationInWindow)
                setFrameOrigin(NSPoint(x: pointer.x - dragOffset.x, y: pointer.y - dragOffset.y))
                return
            }
        case .leftMouseUp:
            if dragOffset != nil {
                dragOffset = nil
                return
            }
        case .keyDown:
            if editor != nil, handleEditingKey(event) { return }
        default:
            break
        }
        super.sendEvent(event)
    }

    override func performClose(_ sender: Any?) {
        if editor == nil {
            close()
        } else {
            closeAfterSave = true
            saveEditing()
        }
    }

    override func resignKey() {
        super.resignKey()
        saveEditing()
    }

    private func isNoteBody(at point: NSPoint) -> Bool {
        guard let contentView,
              contentView.bounds.contains(contentView.convert(point, from: nil)) else { return false }
        let interactiveViews = controls + (editor.map { [$0.view] } ?? [])
        return !interactiveViews.contains { $0.bounds.contains($0.convert(point, from: nil)) }
    }

    private func beginEditing(at screenPoint: NSPoint) {
        let host = glassController.hostingController
        var content = host.rootView
        guard let editor = DesktopNoteEditor(text: content.preview.item.content, font: content.preview.historyFont)
        else { return }
        let padding = HistoryItemPreviewContent.contentPadding
        content.preview.showsBody = false
        let headingHeight = title.isEmpty ? 0 : NSHostingController(rootView: content.preview)
            .sizeThatFits(in: NSSize(width: frame.width - 2 * padding, height: .infinity)).height
            + HistoryItemPreviewText.spacing
        host.rootView = content

        self.editor = editor
        let container = glassController.view
        container.addSubview(editor.view)
        NSLayoutConstraint.activate([
            editor.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            editor.view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            editor.view.topAnchor.constraint(equalTo: container.topAnchor, constant: padding + headingHeight),
            editor.view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.controlsHeight)
        ])
        let height = max(frame.height, padding + headingHeight + Self.controlsHeight + 40)
        resize(to: NSSize(width: frame.width, height: min(availableFrame.height, height)))
        container.layoutSubtreeIfNeeded()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(editor.textView)
        let point = editor.textView.convert(convertPoint(fromScreen: screenPoint), from: nil)
        let index = editor.textView.characterIndexForInsertion(at: point)
        let offset = min(index, (editor.originalText as NSString).length)
        editor.textView.setSelectedRange(NSRange(location: offset, length: 0))
    }

    private func handleEditingKey(_ event: NSEvent) -> Bool {
        guard editor?.textView.hasMarkedText() != true else { return false }
        if event.keyCode == kVK_Escape, !isSaving {
            finishEditing()
            return true
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter {
            saveEditing()
            return true
        }
        return false
    }

    private func saveEditing() {
        guard let editor, let onSave, !isSaving else { return }
        editor.textView.unmarkText()
        let text = editor.textView.string
        guard text != editor.originalText else {
            finishEditing()
            return
        }
        isSaving = true
        editor.textView.isEditable = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await onSave(text)
                isSaving = false
                finishEditing()
            } catch {
                isSaving = false
                closeAfterSave = false
                editor.textView.isEditable = true
                editor.showError(AppSettings.shared.localizedString(clipItemEditErrorMessage(error)))
            }
        }
    }

    private func finishEditing() {
        guard let editor else { return }
        self.editor = nil
        makeFirstResponder(nil)
        editor.view.removeFromSuperview()
        let host = glassController.hostingController
        var content = host.rootView
        content.preview.showsBody = true
        host.rootView = content
        resize(to: Self.contentSize(for: content, screenFrame: availableFrame))
        if closeAfterSave {
            closeAfterSave = false
            close()
        }
    }

    private static func makeContent(for item: ClipItem) -> DesktopNoteContent {
        DesktopNoteContent(preview: HistoryItemPreviewText(item: item, historyFont: FontManager.shared.historyFont))
    }

    private static func contentSize(for content: DesktopNoteContent, screenFrame: NSRect) -> NSSize {
        let maxWidth = min(420, screenFrame.width)
        let sizing = NSHostingController(rootView: content.paddedPreview)
        let ideal = sizing.sizeThatFits(in: NSSize(width: maxWidth, height: .infinity))
        let width = min(maxWidth, max(144, ceil(ideal.width)))
        let wrapped = sizing.sizeThatFits(in: NSSize(width: width, height: .infinity))
        return NSSize(width: width, height: min(screenFrame.height, ceil(wrapped.height) + controlsHeight))
    }

    private func installColorStrip(in view: NSView) {
        colorStrip.wantsLayer = true
        colorStrip.isHidden = true
        colorStrip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(colorStrip)
        NSLayoutConstraint.activate([
            colorStrip.leftAnchor.constraint(equalTo: view.leftAnchor),
            colorStrip.topAnchor.constraint(equalTo: view.topAnchor),
            colorStrip.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            colorStrip.widthAnchor.constraint(equalToConstant: 7)
        ])
    }

    private func installControls(in view: NSView, for item: ClipItem) {
        if let onChangeCategory {
            let menu = DesktopNoteCategoryMenu(item: item, onChangeCategory: onChangeCategory) { [weak self] in
                guard let self else { return }
                CategoryManagerWindowCoordinator.shared.open(relativeTo: self)
            }
            let control = NSHostingView(rootView: menu)
            control.sizingOptions = []
            control.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                control.widthAnchor.constraint(equalToConstant: MainViewMetrics.HistoryColumns.rowCategoryWidth),
                control.heightAnchor.constraint(equalToConstant: MainViewMetrics.HistoryColumns.controlColumnWidth)
            ])
            categoryControl = control
            controls.append(control)
        }
        let palette = makeButton("paintpalette", labelKey: "Desktop Note Color", action: #selector(showColors(_:)))
        let close = makeButton("xmark", labelKey: "Remove Desktop Note", action: #selector(performClose(_:)))
        controls.append(contentsOf: [palette, close])
        let stack = NSStackView(views: controls)
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6)
        ])
    }

    private func makeButton(_ symbol: String, labelKey: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        let label = AppSettings.shared.localizedString(labelKey)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
        return button
    }

    @objc private func showColors(_ sender: NSButton) {
        let menu = NSMenu()
        for color in DesktopNoteColor.allCases {
            let title = AppSettings.shared.localizedString(color.rawValue)
            let item = NSMenuItem(title: title, action: #selector(changeColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = color.rawValue
            item.state = color == selectedColor ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY), in: sender)
    }

    @objc private func changeColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let color = DesktopNoteColor(rawValue: key) else { return }
        selectedColor = color
        colorStrip.layer?.backgroundColor = color.fill?.cgColor
        colorStrip.isHidden = color.fill == nil
    }
}

private struct DesktopNoteCategoryMenu: View {
    var item: ClipItem
    let onChangeCategory: (ClipCategoryChange) async throws -> Void
    let onOpenCategoryManager: () -> Void
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HistoryCategoryMenu(
            item: item,
            isSelected: false,
            onChangeCategory: onChangeCategory,
            onOpenCategoryManager: onOpenCategoryManager
        )
        .environment(\.locale, appSettings.appLocale)
    }
}

private struct DesktopNoteContent: View {
    var preview: HistoryItemPreviewText

    var body: some View {
        paddedPreview.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var paddedPreview: some View {
        preview
            .foregroundStyle(.primary)
            .padding(HistoryItemPreviewContent.contentPadding)
    }
}

@MainActor
private final class DesktopNoteEditor {
    let originalText: String
    let view: NSStackView
    let textView: NSTextView
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init?(text: String, font: NSFont) {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return nil }
        originalText = text
        self.textView = textView
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = font
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        textView.defaultParagraphStyle = paragraphStyle
        textView.string = text
        textView.setAccessibilityLabel(AppSettings.shared.localizedString("Content"))

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true
        errorLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view = NSStackView(views: [scroll, errorLabel])
        view.orientation = .vertical
        view.alignment = .width
        view.spacing = 3
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.toolTip = message
        errorLabel.isHidden = false
    }
}

private enum DesktopNoteColor: String, CaseIterable {
    case none = "No Note Color"
    case yellow = "Yellow Note Color"
    case orange = "Orange Note Color"
    case blue = "Blue Note Color"
    case green = "Green Note Color"
    case pink = "Pink Note Color"

    var fill: NSColor? {
        switch self {
        case .none: nil
        case .yellow: NSColor.systemYellow
        case .orange: NSColor.systemOrange
        case .blue: NSColor.systemBlue
        case .green: NSColor.systemGreen
        case .pink: NSColor.systemPink
        }
    }
}
