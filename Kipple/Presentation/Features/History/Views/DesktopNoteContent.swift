import AppKit
import Carbon.HIToolbox
import SwiftUI
import Textual

struct DesktopNoteContent: View {
    static let controlsHeight: CGFloat = 32
    static let windowBorderInset: CGFloat = 6
    static let headerTopInset: CGFloat = 14
    static let maximumAutomaticWidth: CGFloat = 420
    private static let closeClearance: CGFloat = 28

    let item: ClipItem
    let displayMode: AppSettings.DesktopNoteDisplayMode
    let copyLink: (String) -> Void
    let historyFont = FontManager.shared.historyFont
    var showsBody = true
    var selectionRevision = 0
    var allowsRemoteImages = false
    var openURL: OpenURLAction?
    let measurementID = UUID()
    var onDocumentHeightChange: ((CGFloat, UUID) -> Void)?
    var onBlockWidthChange: ((CGFloat, UUID) -> Void)?

    private var sourceApp: String? { HistoryItemPreviewContent.visibleSourceApp(for: item) }
    private var windowTitle: String? { HistoryItemPreviewContent.visibleWindowTitle(for: item) }
    private var sourceURL: URL? { item.metadata?.sourceWebURL }
    private var hasSource: Bool { sourceApp != nil || windowTitle != nil || sourceURL != nil }
    private var hasTitle: Bool { HistoryItemPreviewContent.nonempty(item.title) != nil }
    var bodyCloseInset: CGFloat { hasTitle || hasSource ? 0 : Self.closeClearance }

    func minimumHeight(at width: CGFloat) -> CGFloat {
        ceil(headerHeight(at: width)) + Self.controlsHeight + 40
    }

    var offersRemoteImages: Bool {
        guard showsBody, displayMode == .markdown, !allowsRemoteImages,
              let markdown = try? AttributedString(markdown: item.content) else { return false }
        return markdown.runs.contains { $0.imageURL.map(isRemoteImage) == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    if hasSource {
                        Divider().padding(.horizontal, HistoryItemPreviewContent.contentPadding).padding(.bottom, 8)
                    }
                }
            if showsBody {
                ScrollView(.vertical) {
                    document
                        .id(selectionRevision)
                        .modifier(DesktopNoteTextRegions(allowsSelectionMargin: true))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, HistoryItemPreviewContent.contentPadding)
                        .padding(.trailing, bodyCloseInset)
                        .padding(.bottom, 8)
                        .background {
                            Color.clear
                                .onGeometryChange(for: CGSize.self, of: \.size) { size in
                                    onDocumentHeightChange?(size.height, measurementID)
                                }
                                .id(measurementID)
                        }
                }
                .contentMargins(.trailing, Self.windowBorderInset, for: .scrollIndicators)
                .scrollIndicators(.visible)
            } else {
                Spacer(minLength: 0)
            }
            Divider().padding(.leading, Self.windowBorderInset + 1)
        }
        .padding(.bottom, Self.controlsHeight - 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.primary)
        .environment(\.locale, AppSettings.shared.appLocale)
        .transformEnvironment(\.openURL) { action in
            if let openURL { action = openURL }
        }
    }

    @ViewBuilder
    private var header: some View {
        if hasTitle || hasSource {
            VStack(alignment: .leading, spacing: 0) {
                if hasTitle {
                    HistoryItemPreviewTitle(title: item.title)
                        .textSelection(.enabled)
                        .id(selectionRevision)
                        .modifier(DesktopNoteTextRegions())
                        .frame(minHeight: 24, alignment: .topLeading)
                        .padding(.trailing, Self.closeClearance)
                }
                if hasSource {
                    sourceSection
                        .id(selectionRevision)
                        .background(DesktopNoteSourceRegion().allowsHitTesting(false).accessibilityHidden(true))
                        .padding(.trailing, hasTitle ? 0 : Self.closeClearance)
                }
            }
            .padding(.horizontal, HistoryItemPreviewContent.contentPadding)
            .padding(.top, Self.headerTopInset)
            .padding(.bottom, hasSource ? 8 : 4)
        } else {
            Color.clear.frame(width: 0, height: Self.headerTopInset)
                .allowsHitTesting(false)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sourceApp { sourceText(sourceApp, symbol: "square.grid.2x2", label: "Copied from") }
            if let windowTitle { sourceText(windowTitle, symbol: "macwindow", label: "Source window", maxLines: 2) }
            if let sourceURL { sourceLink(sourceURL) }
        }
        .font(.system(size: 12))
        .padding(.top, hasTitle ? 5 : 0)
        .padding(.bottom, 9)
    }

    private func sourceText(_ value: String, symbol: String, label: LocalizedStringKey, maxLines: Int = 1) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            sourceIcon(symbol)
            Text(verbatim: value)
                .lineLimit(maxLines)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .modifier(DesktopNoteTextRegions())
                .help(value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: value))
    }

    private func sourceLink(_ url: URL) -> some View {
        let address = url.absoluteString
        let displayAddress = String(address.dropFirst((url.scheme?.count ?? 0) + 3))
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Link(destination: url) {
                sourceIcon("arrow.up.right.square")
            }
            .accessibilityLabel(Text("Source Link"))
            .accessibilityValue(Text(verbatim: address))
            Text(verbatim: displayAddress)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .foregroundStyle(Color(nsColor: .linkColor))
                .textSelection(.enabled)
                .modifier(DesktopNoteTextRegions())
        }
        .background(DesktopNoteSourceRegion(isLink: true).allowsHitTesting(false).accessibilityHidden(true))
        .pointerStyle(.link)
        .help(address)
    }

    func headerHeight(at width: CGFloat) -> CGFloat {
        NSHostingController(rootView: header).sizeThatFits(in: NSSize(width: width, height: .infinity)).height
    }

    private func sourceIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(.secondary)
            .frame(width: 16)
            .accessibilityHidden(true)
    }

    // Markdown is laid out asynchronously, so start with its visible text before measuring the rendered view.
    func estimatedWindowSize(in screenFrame: NSRect, minimumWidth: CGFloat) -> NSSize {
        let maxWidth = min(Self.maximumAutomaticWidth, screenFrame.width)
        let sizing = NSHostingController(rootView: VStack(alignment: .leading, spacing: 0) {
            header
            plainDocument(sizingText)
                .padding(.horizontal, HistoryItemPreviewContent.contentPadding)
                .padding(.trailing, bodyCloseInset)
                .padding(.bottom, 8)
        })
        let ideal = sizing.sizeThatFits(in: NSSize(width: maxWidth, height: .infinity))
        let width = min(maxWidth, max(minimumWidth, ceil(ideal.width)))
        let wrapped = sizing.sizeThatFits(in: NSSize(width: width, height: .infinity))
        let height = min(screenFrame.height, ceil(wrapped.height) + Self.controlsHeight)
        return NSSize(width: width, height: height)
    }

    private var sizingText: String {
        guard displayMode == .markdown, let markdown = try? AttributedString(markdown: item.content) else {
            return item.content
        }
        var block: PresentationIntent?
        var text = ""
        for run in markdown.runs {
            let nextBlock = run.presentationIntent
            if block != nextBlock, !text.isEmpty {
                // Estimate a table row across its cells, including space for cell padding.
                let row = tableRow(in: block)
                text += row != nil && row == tableRow(in: nextBlock) ? "    " : "\n"
            }
            block = nextBlock
            text.append(contentsOf: markdown[run.range].characters)
        }
        return text
    }

    private func tableRow(in intent: PresentationIntent?) -> Int? {
        intent?.components.first {
            switch $0.kind {
            case .tableHeaderRow, .tableRow: true
            default: false
            }
        }?.identity
    }

    private func plainDocument(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Font(historyFont))
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var document: some View {
        switch displayMode {
        case .plainText:
            plainDocument(item.content).textSelection(.enabled)
        case .markdown:
            DesktopNoteMarkdown(source: item.content, font: Font(historyFont), allowsRemoteImages: allowsRemoteImages) {
                let paddedWidth = $0 + 2 * HistoryItemPreviewContent.contentPadding + bodyCloseInset
                onBlockWidthChange?(paddedWidth, measurementID)
            }
            .id(allowsRemoteImages)
        }
    }
}

private struct DesktopNoteSourceRegion: NSViewRepresentable {
    var isLink = false

    func makeNSView(context: Context) -> RegionView {
        let view = RegionView()
        view.isLink = isLink
        return view
    }

    func updateNSView(_ view: RegionView, context: Context) {}

    final class RegionView: NSView {
        var isLink = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let note = window as? DesktopNotePanel else { return }
            if isLink {
                note.sourceLinkRegion = self
            } else {
                note.sourceRegion = self
            }
        }
    }
}

private struct DesktopNoteMarkdown: View {
    let source: String
    let font: Font
    let allowsRemoteImages: Bool
    let onBlockWidthChange: (CGFloat) -> Void

    var body: some View {
        StructuredText(markdown: source)
            .font(font)
            .textual.headingStyle(HeadingStyle())
            .textual.paragraphStyle(ParagraphStyle())
            .textual.codeBlockStyle(CodeBlockStyle(onWidthChange: onBlockWidthChange))
            .textual.tableStyle(TableStyle(onWidthChange: onBlockWidthChange))
            .textual.tableCellStyle(TableCellStyle())
            .textual.overflowMode(.scroll)
            .textual.textSelection(.enabled)
            .textual.imageAttachmentLoader(DesktopNoteImageLoader(upstream: .image(), allowsRemote: allowsRemoteImages))
            .textual.emojiAttachmentLoader(DesktopNoteImageLoader(upstream: .emoji(), allowsRemote: allowsRemoteImages))
    }

    private struct HeadingStyle: StructuredText.HeadingStyle {
        private static let fontScales: [CGFloat] = [1.24, 1.16, 1.08, 1, 1, 1]

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .textual.fontScale(Self.fontScales[configuration.headingLevel - 1])
                .fontWeight(.semibold)
                .lineSpacing(3)
                .textual.blockSpacing(.init(top: 10, bottom: 4))
        }
    }

    private struct ParagraphStyle: StructuredText.ParagraphStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .lineSpacing(3)
                .textual.blockSpacing(.init(top: 6))
        }
    }

    private struct TableStyle: StructuredText.TableStyle {
        let onWidthChange: (CGFloat) -> Void

        func makeBody(configuration: Configuration) -> some View {
            Overflow { state in
                StructuredText.DefaultTableStyle()
                    .makeBody(configuration: configuration)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: state.containerWidth.map { $0 * 3 }, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self, of: \.size.width, action: onWidthChange)
                    .modifier(DesktopNoteTextRegions(allowsSelectionMargin: true))
            }
            .textual.tableCellSpacing(horizontal: 1, vertical: 1)
            .textual.blockSpacing(.init(top: 8, bottom: 8))
        }
    }

    private struct CodeBlockStyle: StructuredText.CodeBlockStyle {
        private static let background = DynamicColor(
            light: Color(red: 0.961, green: 0.961, blue: 0.969),
            dark: Color(red: 0.121, green: 0.123, blue: 0.141)
        )
        private static let border = DynamicColor(
            light: Color(red: 210 / 255, green: 210 / 255, blue: 215 / 255),
            dark: Color(red: 66 / 255, green: 66 / 255, blue: 69 / 255)
        )
        let onWidthChange: (CGFloat) -> Void

        func makeBody(configuration: Configuration) -> some View {
            Overflow {
                configuration.label
                    .textual.lineSpacing(.fontScaled(0.39))
                    .textual.fontScale(0.882)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospaced()
                    .modifier(DesktopNoteTextRegions(allowsSelectionMargin: true))
                    .padding(.vertical, 8)
                    .padding(.leading, 14)
                    .onGeometryChange(for: CGFloat.self, of: \.size.width, action: onWidthChange)
            }
            .background(Self.background, in: .rect(cornerRadius: 4))
            .clipShape(.rect(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Self.border, lineWidth: 1))
            .textual.blockSpacing(.fontScaled(top: 0.88, bottom: 0))
        }
    }

    private struct TableCellStyle: StructuredText.TableCellStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .fontWeight(configuration.row == 0 ? .semibold : .regular)
                .lineSpacing(3)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
    }
}

struct DesktopNoteImageLoader<Upstream: AttachmentLoader>: AttachmentLoader {
    let upstream: Upstream
    let allowsRemote: Bool

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> some Attachment {
        guard url.scheme?.lowercased() == "data" || (allowsRemote && isRemoteImage(url)) else {
            throw URLError(.unsupportedURL)
        }
        return try await upstream.attachment(for: url, text: text, environment: environment)
    }
}

private func isRemoteImage(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    return (scheme == "http" || scheme == "https") && url.host != nil
}

private struct DesktopNoteTextRegions: ViewModifier {
    var allowsSelectionMargin = false

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(Text.LayoutKey.self) { layouts in
            GeometryReader { geometry in
                RegionView(
                    lines: layouts.flatMap { anchored in
                        let origin = geometry[anchored.origin]
                        return anchored.layout.map { line in
                            line.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
                        }
                    },
                    allowsSelectionMargin: allowsSelectionMargin
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private struct RegionView: NSViewRepresentable {
        let lines: [CGRect]
        let allowsSelectionMargin: Bool

        func makeNSView(context: Context) -> DesktopNoteTextHitView { DesktopNoteTextHitView() }

        func updateNSView(_ view: DesktopNoteTextHitView, context: Context) {
            view.lines = lines
            view.allowsSelectionMargin = allowsSelectionMargin
        }
    }
}

@MainActor
final class DesktopNoteTextHitView: NSView {
    private static let horizontalSelectionMargin: CGFloat = 12
    private static let verticalSelectionMargin: CGFloat = 4
    var lines: [CGRect] = []
    var allowsSelectionMargin = false

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? DesktopNotePanel)?.registerTextHitView(self)
    }

    func containsText(at windowPoint: NSPoint) -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
        let point = convert(windowPoint, from: nil)
        return visibleRect.contains(point) && lines.contains { $0.contains(point) }
    }

    func nearbySelectionStart(at windowPoint: NSPoint) -> NSPoint? {
        guard allowsSelectionMargin, window != nil, !isHiddenOrHasHiddenAncestor else { return nil }
        if let clip = enclosingScrollView?.contentView,
           !clip.visibleRect.contains(clip.convert(windowPoint, from: nil)) { return nil }
        let point = convert(windowPoint, from: nil)
        let visible = visibleRect
        let dx = Self.horizontalSelectionMargin
        let dy = Self.verticalSelectionMargin
        guard visible.insetBy(dx: -dx, dy: -dy).contains(point) else { return nil }

        var nearest: NSPoint?
        var nearestDistance = CGFloat.infinity
        for line in lines where line.insetBy(dx: -dx, dy: -dy).contains(point) {
            let selectable = line.intersection(visible).insetBy(dx: 0.5, dy: 0.5)
            guard !selectable.isEmpty else { continue }
            let start = NSPoint(x: min(max(point.x, selectable.minX), selectable.maxX),
                                y: min(max(point.y, selectable.minY), selectable.maxY))
            let distance = hypot(point.x - start.x, point.y - start.y)
            if distance < nearestDistance {
                nearest = start
                nearestDistance = distance
            }
        }
        return nearest.map { convert($0, to: nil) }
    }
}

struct DesktopNoteCategoryMenu: View {
    var item: ClipItem
    var showsTitle = false
    let onChangeCategory: (ClipCategoryChange) async throws -> Void
    let onOpenCategoryManager: () -> Void
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HistoryCategoryMenu(
            item: item,
            isSelected: false,
            onChangeCategory: onChangeCategory,
            onOpenCategoryManager: onOpenCategoryManager,
            showsTitle: showsTitle
        )
        .environment(\.locale, appSettings.appLocale)
    }
}

enum DesktopNoteColor: String, CaseIterable, Codable {
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

@MainActor
final class DesktopNoteEditor: NSObject {
    private static let spacing: CGFloat = 6
    private static let toolbarGap: CGFloat = 8
    static let actionsHeight = DesktopNoteEditActions.height + spacing + toolbarGap

    let originalText: String
    let view: NSStackView
    let textView: LiveEditorTextView
    private let onSave: () -> Void
    private let coordinator: SimpleLineNumberCoordinator
    private let actionsView: NSHostingView<DesktopNoteEditActions>
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let scrollTrailingConstraint: NSLayoutConstraint
    private var topConstraint: NSLayoutConstraint?
    private var asksToSaveAsPlainText = false

    var isConfirmingPlainTextSave: Bool { asksToSaveAsPlainText && !errorLabel.isHidden }

    init(text: String, onCancel: @escaping () -> Void, onSave: @escaping () -> Void) {
        let editor = SimpleLineNumberView(
            text: .constant(text), font: FontManager.shared.editorFont, isEditable: true,
            onDoubleClick: nil, onEscape: nil, textColor: .textColor, onScrollChange: nil
        )
        let coordinator = editor.makeCoordinator()
        let (scroll, textView) = editor.makeEditor(using: coordinator)
        originalText = text
        self.textView = textView
        self.onSave = onSave
        self.coordinator = coordinator
        actionsView = NSHostingView(rootView: DesktopNoteEditActions(onCancel: onCancel, onSave: onSave))
        scroll.scrollerStyle = .overlay
        textView.setAccessibilityLabel(AppSettings.shared.localizedString("Content"))

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true
        errorLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let scrollContainer = NSView()
        scrollContainer.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let trailing = scroll.trailingAnchor.constraint(equalTo: scrollContainer.trailingAnchor)
        scrollTrailingConstraint = trailing
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: scrollContainer.leadingAnchor),
            trailing,
            scroll.topAnchor.constraint(equalTo: scrollContainer.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: scrollContainer.bottomAnchor)
        ])
        view = NSStackView(views: [scrollContainer, errorLabel, actionsView])
        super.init()
        view.orientation = .vertical
        view.alignment = .width
        view.spacing = Self.spacing
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    func install(in container: NSView, headerHeight: CGFloat, bodyCloseInset: CGFloat) {
        let padding = HistoryItemPreviewContent.contentPadding
        container.addSubview(view)
        let top = view.topAnchor.constraint(equalTo: container.topAnchor, constant: headerHeight)
        topConstraint = top
        scrollTrailingConstraint.constant = -bodyCloseInset
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            top,
            view.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -(DesktopNoteContent.controlsHeight + Self.toolbarGap)
            )
        ])
    }

    func updateHeader(height: CGFloat, bodyCloseInset: CGFloat) {
        topConstraint?.constant = height
        scrollTrailingConstraint.constant = -bodyCloseInset
    }

    func setSaving(_ isSaving: Bool) {
        textView.isEditable = !isSaving
        actionsView.rootView.isSaving = isSaving
    }

    func focus(in window: NSWindow, scrollProgress: CGFloat) {
        window.makeFirstResponder(textView)
        let index = scrollProgress > 0 ? scrollTo(progress: scrollProgress) : 0
        let offset = max(0, min(index, originalText.utf16.count))
        let range = NSRange(location: offset, length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    private func scrollTo(progress: CGFloat) -> Int {
        guard let scroll = textView.enclosingScrollView, let container = textView.textContainer else { return 0 }
        textView.layoutManager?.ensureLayout(for: container)
        scroll.layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        let document = clip.documentRect
        let offset = document.minY + progress * max(0, document.height - clip.bounds.height)
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: offset))
        scroll.reflectScrolledClipView(clip)
        let point = NSPoint(x: textView.textContainerOrigin.x, y: clip.documentVisibleRect.minY + 1)
        return textView.characterIndexForInsertion(at: point)
    }

    func handleShortcut(_ event: NSEvent) -> Bool {
        switch AppSettings.shared.editorHotkey(for: event) {
        case .save:
            onSave()
        case .clear:
            clear()
        case nil:
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard modifiers == .command,
                  event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter else { return false }
            onSave()
        }
        return true
    }

    func makeToolsMenu() -> NSMenu {
        let menu = NSMenu()
        addTool("editor.trim", action: #selector(trim), to: menu)
        for format in ClipboardTextFormat.allCases {
            let item = addTool("editor.format.\(format.rawValue)", action: #selector(formatText(_:)), to: menu)
            item.representedObject = format.rawValue
        }
        menu.addItem(.separator())
        addTool("Clear", action: #selector(clear), to: menu)
        return menu
    }

    func showError(_ message: String) {
        asksToSaveAsPlainText = false
        errorLabel.stringValue = message
        errorLabel.toolTip = message
        errorLabel.isHidden = false
    }

    func showSaveError(_ error: Error) {
        showError(AppSettings.shared.localizedString(clipItemEditErrorMessage(error)))
        if case .richTextLossRequiresConfirmation = error as? ClipItemEditError {
            asksToSaveAsPlainText = true
        }
    }

    @discardableResult
    private func addTool(_ key: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let title = AppSettings.shared.localizedString(key)
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func trim() {
        textView.unmarkText()
        replaceText(with: textView.string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @objc private func formatText(_ item: NSMenuItem) {
        guard let key = item.representedObject as? String, let format = ClipboardTextFormat(rawValue: key) else { return }
        textView.unmarkText()
        do {
            replaceText(with: try ClipboardTextFormatter.format(textView.string, as: format))
        } catch {
            let detail = (error as? ClipboardTextFormatter.FormatError)?.detail ?? error.localizedDescription
            let message = AppSettings.shared.localizedString("editor.format.error.invalid")
            showError(String(format: message, format.localizedName, detail))
        }
    }

    @objc private func clear() {
        textView.unmarkText()
        replaceText(with: "")
    }

    private func replaceText(with text: String) {
        errorLabel.isHidden = true
        guard textView.isEditable, text != textView.string else { return }
        let range = NSRange(location: 0, length: textView.attributedString().length)
        textView.breakUndoCoalescing()
        _ = textView.performValidatedReplacement(in: range, with: NSAttributedString(string: text))
        textView.breakUndoCoalescing()
    }
}

private struct DesktopNoteEditActions: View {
    static let height: CGFloat = 28

    let onCancel: () -> Void
    let onSave: () -> Void
    var isSaving = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Button("Cancel", action: onCancel)
                .buttonStyle(style(
                    fill: colorScheme == .dark ? .white.opacity(0.055) : Color(nsColor: .textBackgroundColor),
                    foreground: .primary,
                    border: .primary.opacity(0.17)
                ))
            Button("Save", action: onSave)
                .buttonStyle(style(fill: ClipEditorButtonStyle.accent, foreground: .white, border: .clear))
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .disabled(isSaving)
        .environment(\.locale, AppSettings.shared.appLocale)
    }

    private func style(fill: Color, foreground: Color, border: Color) -> ClipEditorButtonStyle {
        ClipEditorButtonStyle(fill: fill, foreground: foreground, border: border, horizontalPadding: 8, height: Self.height)
    }
}
