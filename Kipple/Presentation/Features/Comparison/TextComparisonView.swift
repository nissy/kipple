import SwiftUI

struct TextComparisonView: View {
    let content: TextComparisonWindow.Content
    let openPermissions: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Group {
            switch content {
            case let .comparison(comparison):
                ComparisonEditor(comparison: comparison)
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
    let comparison: TextComparison

    @State private var currentChange = 0
    @Environment(\.colorScheme) private var colorScheme

    private let gutterWidth: CGFloat = 55
    private var editorColor: Color { Color(nsColor: .textBackgroundColor) }
    private var accent: Color { colorScheme == .dark ? .mint : Color(red: 0.05, green: 0.45, blue: 0.4) }

    var body: some View {
        ScrollViewReader { scroll in
            VStack(spacing: 0) {
                headers
                editor
                footer(scroll)
            }
            .padding(.horizontal, 8)
            .background(accent.opacity(0.05))
            .onAppear {
                if let first = comparison.changeRows.first {
                    scroll.scrollTo(first, anchor: .top)
                }
            }
        }
    }

    private var headers: some View {
        HStack(spacing: 0) {
            heading("Comparison Clipboard")
            Divider().frame(height: 38)
            heading("Comparison Selection")
        }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var editor: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / 2
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(comparison.rows.indices, id: \.self) { index in
                        row(comparison.rows[index], width: width)
                            .id(index)
                    }
                }
            }
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
        .clipShape(.rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator).allowsHitTesting(false) }
    }

    private var paneBackground: some View {
        HStack(spacing: 0) {
            (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                .frame(width: gutterWidth)
            Divider()
            editorColor
        }
        .background(editorColor)
    }

    private func row(_ row: TextComparison.Row, width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            cell(row.left, kind: row.kind, isSelection: false).frame(width: width)
            cell(row.right, kind: row.kind, isSelection: true).frame(width: width)
        }
        .background {
            HStack(spacing: 0) {
                cellBackground(row.left, kind: row.kind, isSelection: false)
                cellBackground(row.right, kind: row.kind, isSelection: true)
            }
        }
    }

    private func cell(_ line: TextComparison.Line?, kind: TextComparison.Row.Kind, isSelection: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(spacing: 5) {
                if let line {
                    Text(line.number, format: .number.grouping(.never))
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11).monospacedDigit())
                    if kind == .inserted || kind == .removed {
                        Image(systemName: kind == .inserted ? "plus.square.fill" : "minus.square.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(kind == .inserted ? accent : Color.red)
                            .accessibilityLabel(kind == .inserted ? Text("Inserted Line") : Text("Removed Line"))
                    } else if line.lineBreakChanged {
                        let label: LocalizedStringKey = isSelection ? "Inserted Line Break" : "Removed Line Break"
                        Image(systemName: "return")
                            .font(.system(size: 11))
                            .foregroundStyle(isSelection ? accent : Color.red)
                            .accessibilityLabel(Text(label))
                            .help(label)
                    }
                }
            }
            .frame(width: gutterWidth - 6, alignment: .trailing)
            .padding(.trailing, 6)

            if let line {
                Text(kind == .replaced ? highlighted(line) : AttributedString(line.text))
                    .font(.system(size: 14, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 33, alignment: .topLeading)
    }

    private func cellBackground(
        _ line: TextComparison.Line?,
        kind: TextComparison.Row.Kind,
        isSelection: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth + 1)
            if let line {
                changedLineBackground(line, kind: kind, isSelection: isSelection)
            } else {
                Color.secondary.opacity(0.10)
            }
        }
    }

    private func changedLineBackground(
        _ line: TextComparison.Line,
        kind: TextComparison.Row.Kind,
        isSelection: Bool
    ) -> Color {
        switch kind {
        case .equal:
            .clear
        case .removed:
            .red.opacity(0.12)
        case .inserted:
            accent.opacity(0.14)
        case .replaced:
            if !line.hasChanges {
                .clear
            } else if !isSelection && line.changes.isEmpty {
                Color.red.opacity(0.12)
            } else {
                accent.opacity(0.14)
            }
        }
    }

    private func highlighted(_ line: TextComparison.Line) -> AttributedString {
        var result = AttributedString()
        var start = line.text.startIndex
        for range in line.changes {
            result += AttributedString(String(line.text[start..<range.lowerBound]))
            var fragment = AttributedString(String(line.text[range]))
            fragment.backgroundColor = accent.opacity(0.34)
            result += fragment
            start = range.upperBound
        }
        result += AttributedString(String(line.text[start...]))
        return result
    }

    private func footer(_ scroll: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            if comparison.changeRows.isEmpty {
                Text("The Text Matches")
            } else {
                Text("There Are Differences")
            }
            Spacer()
            if comparison.changeRows.count > 1 {
                navigationButton("Previous Difference", icon: "chevron.up", offset: -1, scroll: scroll)
                navigationButton("Next Difference", icon: "chevron.down", offset: 1, scroll: scroll)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 5)
        .frame(height: 40)
    }

    private func navigationButton(
        _ label: LocalizedStringKey, icon: String, offset: Int, scroll: ScrollViewProxy
    ) -> some View {
        let target = currentChange + offset
        return Button {
            guard comparison.changeRows.indices.contains(target) else { return }
            currentChange = target
            withAnimation { scroll.scrollTo(comparison.changeRows[target], anchor: .top) }
        } label: {
            Label(label, systemImage: icon).labelStyle(.titleAndIcon)
        }
        .help(label)
        .disabled(!comparison.changeRows.indices.contains(target))
    }
}
