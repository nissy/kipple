import AppKit
import SwiftUI
import Textual

struct DesktopNoteContent: View {
    static let controlsHeight: CGFloat = 32

    let item: ClipItem
    let displayMode: AppSettings.DesktopNoteDisplayMode
    let historyFont = FontManager.shared.historyFont
    var showsBody = true
    var openURL: OpenURLAction?

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryItemPreviewText.spacing) {
            if HistoryItemPreviewContent.nonempty(item.title) != nil {
                titlePreview
                    .textSelection(.enabled)
                    .modifier(DesktopNoteTextRegions())
                    .padding(.horizontal, HistoryItemPreviewContent.contentPadding)
            }
            if showsBody {
                ScrollView(.vertical) {
                    document
                        .modifier(DesktopNoteTextRegions())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, HistoryItemPreviewContent.contentPadding)
                        .padding(.bottom, 8)
                }
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
    var sizingPreview: some View {
        HistoryItemPreviewText(item: item, historyFont: historyFont)
            .padding(HistoryItemPreviewContent.contentPadding)
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
final class DesktopNoteResizeHandle: NSImageView {
    private var dragStart: (frame: NSRect, pointer: NSPoint)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let label = AppSettings.shared.localizedString("Resize Desktop Note")
        let size = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: label)?
            .withSymbolConfiguration(size)
        contentTintColor = .secondaryLabelColor
        imageScaling = .scaleNone
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = label
        setAccessibilityLabel(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStart = (window.frame, window.convertPoint(toScreen: event.locationInWindow))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let note = window as? DesktopNotePanel, let dragStart else { return }
        let pointer = note.convertPoint(toScreen: event.locationInWindow)
        let displacement = NSPoint(x: pointer.x - dragStart.pointer.x, y: pointer.y - dragStart.pointer.y)
        note.resizeFromBottomRight(startFrame: dragStart.frame, displacement: displacement)
    }

    override func mouseUp(with _: NSEvent) {
        dragStart = nil
    }
}

@MainActor
final class DesktopNoteEditor {
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
