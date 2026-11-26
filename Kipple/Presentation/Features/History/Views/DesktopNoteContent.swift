import AppKit
import Carbon.HIToolbox
import SwiftUI
import Textual

struct DesktopNoteContent: View {
    static let controlsHeight: CGFloat = 32
    static let windowBorderInset: CGFloat = 6

    let item: ClipItem
    let displayMode: AppSettings.DesktopNoteDisplayMode
    let historyFont = FontManager.shared.historyFont
    var showsBody = true
    var selectionRevision = 0
    var allowsRemoteImages = false
    var openURL: OpenURLAction?

    var sourceLinkHeight: CGFloat { showsBody && item.metadata?.sourceWebURL != nil ? 22 : 0 }

    var sourceLinkVerticalRange: Range<CGFloat> {
        Self.controlsHeight..<(Self.controlsHeight + sourceLinkHeight)
    }

    func minimumHeight(startingAt height: CGFloat) -> CGFloat {
        // Leave reading space even when the title wraps onto two lines.
        let titleHeight: CGFloat = HistoryItemPreviewContent.nonempty(item.title) == nil ? 0 : 40
        return height + titleHeight + sourceLinkHeight
    }

    var offersRemoteImages: Bool {
        guard showsBody, displayMode == .markdown, !allowsRemoteImages,
              let markdown = try? AttributedString(markdown: item.content) else { return false }
        return markdown.runs.contains { $0.imageURL.map(isRemoteImage) == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryItemPreviewText.spacing) {
            if HistoryItemPreviewContent.nonempty(item.title) != nil {
                titlePreview
                    .textSelection(.enabled)
                    .id(selectionRevision)
                    .modifier(DesktopNoteTextRegions())
                    .padding(.horizontal, HistoryItemPreviewContent.contentPadding)
            }
            if showsBody {
                VStack(spacing: 0) {
                    ScrollView(.vertical) {
                        document
                            .id(selectionRevision)
                            .modifier(DesktopNoteTextRegions(
                                sourceText: displayMode == .plainText ? item.content : nil
                            ))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, HistoryItemPreviewContent.contentPadding)
                            .padding(.bottom, 8)
                    }
                    .contentMargins(.trailing, Self.windowBorderInset, for: .scrollIndicators)
                    .scrollIndicators(.visible)

                    if let url = item.metadata?.sourceWebURL {
                        HistorySourceLink(url: url)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, HistoryItemPreviewContent.contentPadding)
                            .frame(height: sourceLinkHeight)
                    }
                }
            }
        }
        .padding(.top, HistoryItemPreviewContent.contentPadding)
        .padding(.bottom, Self.controlsHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.primary)
        .transformEnvironment(\.openURL) { action in
            if let openURL { action = openURL }
        }
    }

    var titlePreview: some View {
        HistoryItemPreviewTitle(title: item.title)
    }

    // Estimate the initial window size without laying out the whole scrollable document twice.
    func estimatedWindowSize(in screenFrame: NSRect, minimumWidth: CGFloat) -> NSSize {
        let maxWidth = min(420, screenFrame.width)
        let sizing = NSHostingController(rootView: HistoryItemPreviewText(item: item, historyFont: historyFont)
            .padding(HistoryItemPreviewContent.contentPadding))
        let ideal = sizing.sizeThatFits(in: NSSize(width: maxWidth, height: .infinity))
        let width = min(maxWidth, max(minimumWidth, ceil(ideal.width)))
        let wrapped = sizing.sizeThatFits(in: NSSize(width: width, height: .infinity))
        let height = min(screenFrame.height, ceil(wrapped.height) + Self.controlsHeight + sourceLinkHeight)
        return NSSize(width: width, height: height)
    }

    @ViewBuilder
    private var document: some View {
        switch displayMode {
        case .plainText:
            Text(verbatim: item.content)
                .font(Font(historyFont))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .markdown:
            DesktopNoteMarkdown(source: item.content, font: Font(historyFont), allowsRemoteImages: allowsRemoteImages)
                .id(allowsRemoteImages)
        }
    }
}

private struct DesktopNoteMarkdown: View {
    let source: String
    let font: Font
    let allowsRemoteImages: Bool

    var body: some View {
        StructuredText(markdown: source)
            .font(font)
            .textual.headingStyle(HeadingStyle())
            .textual.paragraphStyle(ParagraphStyle())
            .textual.codeBlockStyle(CodeBlockStyle())
            .textual.tableStyle(TableStyle())
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
        func makeBody(configuration: Configuration) -> some View {
            Overflow { state in
                StructuredText.DefaultTableStyle()
                    .makeBody(configuration: configuration)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: state.containerWidth.map { $0 * 3 }, alignment: .leading)
                    .modifier(DesktopNoteTextRegions())
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

        func makeBody(configuration: Configuration) -> some View {
            Overflow {
                configuration.label
                    .textual.lineSpacing(.fontScaled(0.39))
                    .textual.fontScale(0.882)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospaced()
                    .modifier(DesktopNoteTextRegions())
                    .padding(.vertical, 8)
                    .padding(.leading, 14)
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
    var sourceText: String?

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
                    sourceLayout: sourceText != nil && layouts.count == 1 ? layouts.first : nil,
                    sourceText: sourceText,
                    sourceOrigin: layouts.first.map { geometry[$0.origin] } ?? .zero
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private struct RegionView: NSViewRepresentable {
        let lines: [CGRect]
        let sourceLayout: Text.LayoutKey.AnchoredLayout?
        let sourceText: String?
        let sourceOrigin: CGPoint

        func makeNSView(context: Context) -> DesktopNoteTextHitView { DesktopNoteTextHitView() }

        func updateNSView(_ view: DesktopNoteTextHitView, context: Context) {
            view.lines = lines
            view.sourceLayout = sourceLayout?.layout
            view.sourceText = sourceText
            view.sourceOrigin = sourceOrigin
        }
    }
}

@MainActor
final class DesktopNoteTextHitView: NSView {
    var lines: [CGRect] = []
    var sourceLayout: Text.Layout?
    var sourceText: String?
    var sourceOrigin = CGPoint.zero

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

    func sourceOffset(at windowPoint: NSPoint) -> Int? {
        let point = convert(windowPoint, from: nil)
        guard window != nil, !isHiddenOrHasHiddenAncestor, visibleRect.contains(point),
              let sourceLayout, let sourceText else { return nil }
        let x = point.x - sourceOrigin.x
        let y = point.y - sourceOrigin.y
        let paragraphs = sourceText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var paragraph = 0
        var start = sourceLayout.first?.flatMap(\.characterIndices).min()
        var last: Text.Layout.CharacterIndex?
        for (lineNumber, line) in sourceLayout.enumerated() {
            let indices = line.flatMap(\.characterIndices)
            let first = indices.min()
            // SwiftUI indices restart after a hard line break, but continue across soft wraps.
            if lineNumber > 0, first.flatMap({ index in last.map { index <= $0 } }) ?? true {
                paragraph += 1
                start = first
            }
            if (line.typographicBounds.rect.minY...line.typographicBounds.rect.maxY).contains(y) {
                guard paragraphs.indices.contains(paragraph) else { return nil }
                let text = paragraphs[paragraph]
                let glyph = line.flatMap { $0 }.min {
                    abs($0.typographicBounds.rect.midX - x) < abs($1.typographicBounds.rect.midX - x)
                }
                let offset = glyph?.characterIndices.min().flatMap { index in start?.distance(to: index) } ?? 0
                guard (0...text.utf16.count).contains(offset) else { return nil }
                return text.startIndex.utf16Offset(in: sourceText) + offset
            }
            last = indices.max()
        }
        return nil
    }
}

struct DesktopNoteCategoryMenu: View {
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

enum DesktopNoteColor: String, CaseIterable {
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
    private static let spacing: CGFloat = 3
    static let actionsHeight = DesktopNoteEditActions.height + spacing

    let originalText: String
    let view: NSStackView
    let textView: LiveEditorTextView
    private let onSave: () -> Void
    private let coordinator: SimpleLineNumberCoordinator
    private let actionsView: NSHostingView<DesktopNoteEditActions>
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
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
        view = NSStackView(views: [scroll, errorLabel, actionsView])
        super.init()
        view.orientation = .vertical
        view.alignment = .width
        view.spacing = Self.spacing
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    func install(in container: NSView, headingHeight: CGFloat) {
        let padding = HistoryItemPreviewContent.contentPadding
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: padding + headingHeight),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DesktopNoteContent.controlsHeight)
        ])
    }

    func setSaving(_ isSaving: Bool) {
        textView.isEditable = !isSaving
        actionsView.rootView.isSaving = isSaving
    }

    func focus(at screenPoint: NSPoint, in window: NSWindow, sourceOffset: Int?, scrollProgress: CGFloat) {
        if sourceOffset == nil, scrollProgress > 0 {
            // The Markdown preview can reflow or omit syntax, so its coordinates cannot place a source caret.
            scrollTo(progress: scrollProgress)
            window.makeFirstResponder(nil)
            return
        }
        window.makeFirstResponder(textView)
        let point = textView.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let index = sourceOffset ?? textView.characterIndexForInsertion(at: point)
        let offset = max(0, min(index, (originalText as NSString).length))
        let range = NSRange(location: offset, length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    private func scrollTo(progress: CGFloat) {
        guard let scroll = textView.enclosingScrollView, let container = textView.textContainer else { return }
        textView.layoutManager?.ensureLayout(for: container)
        scroll.layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        let document = clip.documentRect
        let offset = document.minY + progress * max(0, document.height - clip.bounds.height)
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: offset))
        scroll.reflectScrolledClipView(clip)
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
