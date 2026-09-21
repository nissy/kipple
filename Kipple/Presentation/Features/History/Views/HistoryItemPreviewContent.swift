import AppKit
import SwiftUI

struct HistoryItemPreviewContent: View {
    let item: ClipItem
    let categories: [UserCategory]
    let historyFont: NSFont
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title = Self.nonempty(item.title) {
                Text(verbatim: title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(title)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(verbatim: Self.makePreviewText(for: item))
                .font(Font(historyFont))
                .lineSpacing(3)
                .lineLimit(previewLineLimit)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            CategoryLabelsView(categories: categories, isPreview: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            metadataSection
        }
        .foregroundStyle(.primary)
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var previewLineLimit: Int {
        let lineHeight = ceil(historyFont.ascender - historyFont.descender + historyFont.leading + 3)
        return max(1, min(10, Int(220 / max(1, lineHeight))))
    }

    private var metadataSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            if let sourceApp = Self.nonempty(item.sourceApp) {
                GridRow(alignment: .firstTextBaseline) {
                    metadataLabel("Copied from")
                    Text(verbatim: localizedAppName(sourceApp))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(sourceApp)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let windowTitle = Self.visibleWindowTitle(sourceApp: item.sourceApp, windowTitle: item.windowTitle) {
                GridRow(alignment: .firstTextBaseline) {
                    metadataLabel("Source window")
                    Text(verbatim: localizedWindowTitle(windowTitle))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(windowTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GridRow(alignment: .firstTextBaseline) {
                metadataLabel("Copied at")
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        timestamp
                        Spacer(minLength: 0)
                        characterCount
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        timestamp
                        characterCount.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .foregroundStyle(.secondary)
            .fixedSize()
            .gridColumnAlignment(.leading)
    }

    private var timestamp: some View {
        Text(verbatim: item.formattedTimestamp)
            .monospacedDigit()
            .fixedSize()
    }

    private var characterCount: some View {
        Text("\(item.characterCount.formatted(.number.locale(locale))) characters")
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize()
    }

    private func localizedAppName(_ name: String) -> String {
        name == "External Source" ? String(localized: "External Source", locale: locale) : name
    }

    private func localizedWindowTitle(_ title: String) -> String {
        if title == "Quick Editor" || title == "Live Editor" {
            return String(localized: "Live Editor", locale: locale)
        }
        return title
    }

    static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func visibleWindowTitle(sourceApp: String?, windowTitle: String?) -> String? {
        guard let windowTitle = nonempty(windowTitle), windowTitle != nonempty(sourceApp) else { return nil }
        return windowTitle
    }

    static func makePreviewText(for item: ClipItem, maxLength: Int = 500) -> String {
        String(item.content.prefix(maxLength))
    }
}
