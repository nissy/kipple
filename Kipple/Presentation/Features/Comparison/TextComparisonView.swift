import SwiftUI

struct TextComparisonView: View {
    let content: TextComparisonWindow.Content
    let openPermissions: () -> Void
    let closeAfterCopy: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Group {
            switch content {
            case let .comparison(comparison):
                ComparisonEditor(comparison: comparison, closeAfterCopy: closeAfterCopy)
            case .accessibilityRequired:
                notice(
                    "Selection Access Required",
                    icon: "lock",
                    description: "Allow \(Text(AccessibilityPermissionLabel.title)) to read selected text."
                ) { Button("Open Permissions", action: openPermissions) }
            case .clipboardUnavailable:
                notice(
                    "Clipboard Unavailable",
                    icon: "clipboard",
                    description: "Check Clipboard Access in Settings → Permission."
                ) { Button("Open Permissions", action: openPermissions) }
            case .noClipboardText:
                notice("No Clipboard Text", icon: "clipboard", description: "Copy some text before comparing.") {}
            case .noSelection:
                notice(
                    "No Selected Text",
                    icon: "text.cursor",
                    description: "Select text in the frontmost app and try the shortcut again."
                ) {}
            case .unsupportedSelection:
                notice(
                    "Selection Includes an Embedded Object",
                    icon: "text.cursor",
                    description: "Select text without embedded images or emoji and try again."
                ) {}
            case .textTooLong:
                notice(
                    "Text Too Long to Compare",
                    icon: "exclamationmark.triangle",
                    description: "Comparison supports up to 80,000 characters on each side."
                ) {}
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color(nsColor: .labelColor))
        .environment(\.locale, settings.appLocale)
    }

    private func notice<Actions: View>(
        _ title: LocalizedStringKey,
        icon: String,
        description: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(description)
        } actions: {
            actions()
        }
    }
}

private struct ComparisonEditor: View {
    private struct DifferenceHighlight {
        let background: Color
        let foreground: Color

        static let standard = Self(background: Color(red: 1, green: 0.68, blue: 0.30), foreground: .black)
        static let current = Self(background: Color(red: 0.42, green: 0.81, blue: 1), foreground: .black)
    }

    let comparison: TextComparison
    let closeAfterCopy: () -> Void

    @State private var currentChange = 0
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var copyFailed = false
    @State private var copyTask: Task<Void, Never>?

    private var gutterWidth: CGFloat { 27 + CGFloat(String(comparison.rows.count).count) * 7 }
    private let editorShape = RoundedRectangle(cornerRadius: KippleGlassMetrics.editorCornerRadius, style: .continuous)

    var body: some View {
        VStack(spacing: 8) {
            headers
            editor
            footer
        }
        .padding(.horizontal, MainViewMetrics.contentHorizontalInset)
        .padding(.vertical, 12)
        .onAppear {
            if let first = comparison.differences.first {
                scrollPosition.scrollTo(id: first.row, anchor: .top)
            }
        }
        .onDisappear {
            copyTask?.cancel()
            copyTask = nil
        }
    }

    private var headers: some View {
        HStack(spacing: 0) {
            heading("Comparison Clipboard")
                .padding(.leading, 2)
            heading("Comparison Selection")
                .padding(.leading, 9)
                .overlay(alignment: .trailing) { copySelectionButton }
        }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .frame(maxWidth: .infinity, minHeight: KippleButtonMetrics.editorControlHeight, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var copySelectionButton: some View {
        Button(action: copySelection) {
            Label("Copy", systemImage: copyFailed ? "exclamationmark.triangle" : "doc.on.doc")
                .labelStyle(.titleAndIcon)
                .frame(
                    height: KippleButtonMetrics.editorControlHeight - 2 * KippleButtonMetrics.prominentVerticalPadding
                )
        }
        .buttonStyle(ProminentButtonStyle())
        .disabled(copyTask != nil)
        .opacity(copyTask != nil ? KippleButtonAppearance.disabledOpacity : 1)
        .accessibilityLabel("Copy Selected Text")
        .accessibilityValue(copyFailed ? Text("Could Not Copy Text") : Text(""))
        .help(copyFailed ? "Could Not Copy Text" : "Copy Selected Text")
    }

    private func copySelection() {
        guard copyTask == nil else { return }
        copyFailed = false
        copyTask = Task {
            let copied = await ModernClipboardService.shared.writeToClipboardOnly(
                comparison.selection, preservingRichText: false
            ) { !Task.isCancelled }
            guard !Task.isCancelled else { return }
            copyTask = nil
            if copied {
                closeAfterCopy()
            } else {
                copyFailed = true
            }
        }
    }

    private var editor: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / 2
            let differences = comparison.differences
            let activeDifference = differences.count > 1 && differences.indices.contains(currentChange)
                ? differences[currentChange].id : nil
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(comparison.rows.indices, id: \.self) { index in
                        row(comparison.rows[index], width: width, activeDifference: activeDifference)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition($scrollPosition)
            .contentMargins(.vertical, 7, for: .scrollContent)
            .background {
                HStack(spacing: 0) {
                    paneBackground
                    paneBackground
                }
            }
            .overlay {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
        }
        .background(KippleGlassAppearance.readOnlyEditorFill)
        .clipShape(editorShape)
        .overlay { editorShape.strokeBorder(KippleGlassAppearance.readOnlyEditorStroke).allowsHitTesting(false) }
    }

    private var paneBackground: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth)
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            Color.clear
        }
        .allowsHitTesting(false)
    }

    private func row(_ row: TextComparison.Row, width: CGFloat, activeDifference: Int?) -> some View {
        let isActive = activeDifference.map { difference in
            row.left?.containsDifference(difference) == true || row.right?.containsDifference(difference) == true
        } ?? false
        return HStack(alignment: .top, spacing: 0) {
            cell(row.left, kind: row.kind, isSelection: false, activeDifference: activeDifference).frame(width: width)
            cell(row.right, kind: row.kind, isSelection: true, activeDifference: activeDifference).frame(width: width)
        }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func cell(
        _ line: TextComparison.Line?, kind: TextComparison.Row.Kind, isSelection: Bool, activeDifference: Int?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(spacing: 5) {
                if let line {
                    if kind == .inserted || kind == .removed {
                        changeMarker(
                            kind == .inserted ? "plus" : "minus",
                            isActive: line.text.isEmpty && activeDifference != nil && line.lineBreakDifference == activeDifference
                        )
                            .accessibilityLabel(kind == .inserted ? Text("Inserted Line") : Text("Removed Line"))
                    } else if let lineBreakDifference = line.lineBreakDifference {
                        let label: LocalizedStringKey = isSelection ? "Inserted Line Break" : "Removed Line Break"
                        changeMarker("return", isActive: lineBreakDifference == activeDifference)
                            .accessibilityLabel(Text(label))
                            .help(label)
                    }
                    Text(line.number, format: .number.grouping(.never))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .font(.system(size: 11).monospacedDigit())
                }
            }
            .frame(width: gutterWidth - 6, alignment: .trailing)
            .padding(.trailing, 6)

            if let line {
                Text(highlighted(line, activeDifference: activeDifference))
                    .font(.system(size: 13, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 7)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 29, alignment: .topLeading)
    }

    private func changeMarker(_ symbol: String, isActive: Bool) -> some View {
        let style = isActive ? DifferenceHighlight.current : .standard
        return Image(systemName: symbol)
            .font(.system(size: 11))
            .foregroundStyle(style.foreground)
            .frame(width: 16, height: 16)
            .background(style.background, in: .rect(cornerRadius: 3))
    }

    private func highlighted(_ line: TextComparison.Line, activeDifference: Int?) -> AttributedString {
        guard !line.changes.isEmpty else { return AttributedString(line.text) }
        var result = AttributedString()
        var start = line.text.startIndex
        for change in line.changes {
            let range = change.range
            let isActive = change.difference == activeDifference
            let style = isActive ? DifferenceHighlight.current : .standard
            result += AttributedString(String(line.text[start..<range.lowerBound]))
            var fragment = AttributedString(String(line.text[range]))
            fragment.backgroundColor = style.background
            fragment.foregroundColor = style.foreground
            if isActive { fragment.underlineStyle = Text.LineStyle(pattern: .solid, color: style.foreground) }
            result += fragment
            start = range.upperBound
        }
        result += AttributedString(String(line.text[start...]))
        return result
    }

    @ViewBuilder
    private var footer: some View {
        if comparison.differences.isEmpty {
            Text("The Text Matches")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if comparison.differences.count > 1 {
            HStack(spacing: MainViewMetrics.toolbarItemSpacing) {
                navigationButton("Previous Difference", icon: "chevron.up", offset: -1)
                navigationButton("Next Difference", icon: "chevron.down", offset: 1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func navigationButton(_ label: LocalizedStringKey, icon: String, offset: Int) -> some View {
        let target = currentChange + offset
        let isEnabled = comparison.differences.indices.contains(target)
        return Button {
            guard isEnabled else { return }
            currentChange = target
            withAnimation { scrollPosition.scrollTo(id: comparison.differences[target].row, anchor: .top) }
        } label: {
            Image(systemName: icon)
                .font(MainViewMetrics.BottomBar.iconFont)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .kippleSystemCircleButton(isEnabled: isEnabled)
        .accessibilityLabel(Text(label))
        .help(label)
        .disabled(!isEnabled)
    }
}
