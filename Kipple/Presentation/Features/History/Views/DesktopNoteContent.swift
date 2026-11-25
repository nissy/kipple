import AppKit
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
    var openURL: OpenURLAction?

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
                ScrollView(.vertical) {
                    document
                        .id(selectionRevision)
                        .modifier(DesktopNoteTextRegions())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, HistoryItemPreviewContent.contentPadding)
                        .padding(.bottom, 8)
                }
                .contentMargins(.trailing, Self.windowBorderInset, for: .scrollIndicators)
                .scrollIndicators(.visible)
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
        let height = min(screenFrame.height, ceil(wrapped.height) + Self.controlsHeight)
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
            DesktopNoteMarkdown(source: item.content, font: Font(historyFont))
        }
    }
}

private struct DesktopNoteMarkdown: View {
    let source: String
    let font: Font

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

private struct DesktopNoteTextRegions: ViewModifier {
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(Text.LayoutKey.self) { layouts in
            GeometryReader { geometry in
                RegionView(lines: layouts.flatMap { anchored in
                    let origin = geometry[anchored.origin]
                    return anchored.layout.map { line in
                        line.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
                    }
                })
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private struct RegionView: NSViewRepresentable {
        let lines: [CGRect]

        func makeNSView(context: Context) -> DesktopNoteTextHitView { DesktopNoteTextHitView() }

        func updateNSView(_ view: DesktopNoteTextHitView, context: Context) { view.lines = lines }
    }
}

@MainActor
final class DesktopNoteTextHitView: NSView {
    var lines: [CGRect] = []

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
    let originalText: String
    let view: NSStackView
    let textView: LiveEditorTextView
    private let coordinator: SimpleLineNumberCoordinator
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(text: String) {
        let editor = SimpleLineNumberView(
            text: .constant(text), font: FontManager.shared.editorFont, isEditable: true,
            onDoubleClick: nil, onEscape: nil, textColor: .textColor, onScrollChange: nil
        )
        let coordinator = editor.makeCoordinator()
        let (scroll, textView) = editor.makeEditor(using: coordinator)
        originalText = text
        self.textView = textView
        self.coordinator = coordinator
        scroll.scrollerStyle = .overlay
        textView.setAccessibilityLabel(AppSettings.shared.localizedString("Content"))

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true
        errorLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view = NSStackView(views: [scroll, errorLabel])
        super.init()
        view.orientation = .vertical
        view.alignment = .width
        view.spacing = 3
        view.translatesAutoresizingMaskIntoConstraints = false
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
        errorLabel.stringValue = message
        errorLabel.toolTip = message
        errorLabel.isHidden = false
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
