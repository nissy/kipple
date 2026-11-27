import AppKit
import Carbon.HIToolbox
import SwiftUI
import Textual

struct DesktopNoteContent: View {
    static let controlsHeight: CGFloat = 32
    static let windowBorderInset: CGFloat = 6
    static let headerTopInset: CGFloat = 14
    static let maximumAutomaticWidth: CGFloat = 420

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
    private var hasTitle: Bool { showsBody && HistoryItemPreviewContent.nonempty(item.title) != nil }

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
                }
                if hasSource {
                    sourceSection
                        .id(selectionRevision)
                        .background(DesktopNoteSourceRegion().allowsHitTesting(false).accessibilityHidden(true))
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
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Link(destination: url) {
                sourceIcon("arrow.up.right.square")
            }
            .accessibilityLabel(Text("Source Link"))
            .accessibilityValue(Text(verbatim: address))
            Text(verbatim: HistorySourceLink.displayAddress(for: url))
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
                let paddedWidth = $0 + 2 * HistoryItemPreviewContent.contentPadding
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
            let clipped = line.intersection(visible)
            guard !clipped.isEmpty else { continue }
            let selectable = clipped.insetBy(dx: min(0.5, clipped.width / 4), dy: 0.5)
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
            itemID: item.id,
            categoryIDs: item.categoryIDs,
            isSelected: false,
            onChangeCategory: onChangeCategory,
            onOpenCategoryManager: onOpenCategoryManager,
            showsTitle: showsTitle
        )
        .environment(\.locale, appSettings.appLocale)
    }
}
