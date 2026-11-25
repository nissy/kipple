import AppKit
import SwiftUI

struct DesktopNoteContent: View {
    var preview: HistoryItemPreviewText
    var openURL: OpenURLAction?

    init(item: ClipItem, displayMode: AppSettings.DesktopNoteDisplayMode) {
        let font = FontManager.shared.historyFont
        preview = HistoryItemPreviewText(item: item, historyFont: font)
        if displayMode == .markdown {
            let text = HistoryItemPreviewContent.makePreviewText(for: item)
            preview.formattedBody = DesktopNoteMarkdown.render(text, baseFont: font)
        }
    }

    var body: some View {
        paddedPreview.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transformEnvironment(\.openURL) { action in
                if let openURL { action = openURL }
            }
    }

    var paddedPreview: some View {
        preview
            .foregroundStyle(.primary)
            .padding(HistoryItemPreviewContent.contentPadding)
    }
}

enum DesktopNoteMarkdown {
    static func render(_ source: String, baseFont: NSFont) -> AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let parsed = try? AttributedString(markdown: source, options: options),
              !parsed.characters.isEmpty else { return nil }

        var result = AttributedString()
        var previous: [PresentationIntent.IntentType] = []
        for run in parsed.runs {
            let block = run.presentationIntent?.components ?? []
            if block != previous {
                if !result.characters.isEmpty {
                    if let row = tableRow(in: block), row == tableRow(in: previous) {
                        result.append(AttributedString("  │  "))
                    } else if result.characters.last != "\n" {
                        result.append(AttributedString("\n"))
                    }
                }
                result.append(AttributedString(blockPrefix(block, following: previous)))
                previous = block
            }
            var text = AttributedString(parsed[run.range])
            text.presentationIntent = nil
            text.font = displayFont(for: run, baseFont: baseFont)
            result.append(text)
        }
        return result
    }

    private static func blockPrefix(
        _ block: [PresentationIntent.IntentType], following previous: [PresentationIntent.IntentType]
    ) -> String {
        let quote = String(repeating: "│ ", count: block.count { $0.kind == .blockQuote })
        let listItems = block.filter {
            if case .listItem = $0.kind { return true }
            return false
        }
        guard let item = listItems.first, case let .listItem(ordinal) = item.kind else { return quote }
        let indent = String(repeating: "  ", count: listItems.count - 1)
        if previous.contains(item) { return quote + indent + "  " }
        let list = block.first { $0.kind == .orderedList || $0.kind == .unorderedList }
        let marker = list?.kind == .orderedList ? "\(ordinal). " : "• "
        return quote + indent + marker
    }

    private static func tableRow(in block: [PresentationIntent.IntentType]) -> Int? {
        block.first {
            switch $0.kind {
            case .tableRow, .tableHeaderRow: true
            default: false
            }
        }?.identity
    }

    private static func displayFont(for run: AttributedString.Runs.Run, baseFont: NSFont) -> Font? {
        let block = run.presentationIntent?.components ?? []
        if run.inlinePresentationIntent?.contains(.code) == true || block.contains(where: {
            if case .codeBlock = $0.kind { return true }
            return false
        }) {
            return .system(size: baseFont.pointSize, design: .monospaced)
        }
        for component in block {
            switch component.kind {
            case let .header(level):
                return .system(size: baseFont.pointSize + CGFloat(max(1, 6 - level)), weight: .semibold)
            case .tableHeaderRow:
                return Font(baseFont).weight(.semibold)
            default:
                continue
            }
        }
        return nil
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
