import AppKit
import SwiftUI

struct ClipDetailsView: View {
    private let originalItem: ClipItem
    private let editingItemID: UUID?
    private let target: ClipItemEditorWindow.Target
    let onClose: () -> Void
    let onSavingChanged: (Bool) -> Void
    @ObservedObject private var adapter = ModernClipboardServiceAdapter.shared
    @ObservedObject private var categoryStore = UserCategoryStore.shared
    @ObservedObject private var fontManager = FontManager.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTitleFocused: Bool
    @State private var title: String
    @State private var content: String
    @State private var categoryChanges: [UUID: Bool] = [:]
    @State private var errorMessage: LocalizedStringKey?
    @State private var isSaving = false

    init(
        item: ClipItem?,
        target: ClipItemEditorWindow.Target,
        onClose: @escaping () -> Void,
        onSavingChanged: @escaping (Bool) -> Void
    ) {
        originalItem = item ?? ClipItem(content: "", sourceApp: "Kipple", isFromEditor: true)
        editingItemID = item?.id
        self.target = target
        self.onClose = onClose
        self.onSavingChanged = onSavingChanged
        _title = State(initialValue: item?.title ?? "")
        _content = State(initialValue: item?.content ?? "")
    }

    private var currentItem: ClipItem? {
        guard let editingItemID else { return originalItem }
        return adapter.history.first { $0.id == editingItemID }
    }
    private var canSave: Bool { !isSaving && currentItem != nil && (editingItemID != nil || !content.isEmpty) }
    private var editedTitle: String? { title == (originalItem.title ?? "") ? nil : title }
    private var editedContent: String? { content == originalItem.content ? nil : content }
    private let accent = ClipEditorButtonStyle.accent
    private let fieldShape = RoundedRectangle(cornerRadius: KippleGlassMetrics.inputCornerRadius)

    private var windowSurface: Color {
        colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(red: 0.925, green: 0.958, blue: 0.959)
    }

    private var titleBarFill: Color {
        colorScheme == .dark ? Color(nsColor: .underPageBackgroundColor) : Color(red: 0.94, green: 0.95, blue: 0.95)
    }

    private var fieldFill: Color {
        colorScheme == .dark ? .white.opacity(0.055) : Color(nsColor: .textBackgroundColor).opacity(0.82)
    }
    private var fieldBorder: Color { .primary.opacity(0.17) }
    private var rulerFill: NSColor {
        if colorScheme == .dark { return .white.withAlphaComponent(0.045) }
        return NSColor(srgbRed: 0.93, green: 0.94, blue: 0.95, alpha: 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let defaultHeight = ClipItemEditorWindow.initialContentSize(for: target).height
            let extraHeight = max(0, geometry.size.height - defaultHeight)
            VStack(spacing: 0) {
                Text(LocalizedStringKey(target.titleKey))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(titleBarFill)
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isHeader)
                Divider()
                form(editorHeight: ClipItemEditorWindow.preferredEditorHeight + extraHeight)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .defaultFocus($isTitleFocused, true)
        .environment(\.locale, appSettings.appLocale)
    }

    private func form(editorHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    if let item = currentItem {
                        editor(for: item, height: editorHeight)
                    } else {
                        Text("Item unavailable")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(windowSurface)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Button(action: cancel) {
                Text("Cancel").frame(minWidth: 86)
            }
            .buttonStyle(ClipEditorButtonStyle(fill: fieldFill, foreground: .primary, border: fieldBorder))
            .disabled(isSaving)
            Button(action: save) {
                Text("Save").frame(minWidth: 68)
            }
            .buttonStyle(ClipEditorButtonStyle(fill: accent, foreground: .white, border: .clear))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSave)
        }
    }

    private func editor(for item: ClipItem, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Title")
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 11)
                    .frame(height: 31)
                    .background(fieldFill, in: fieldShape)
                    .overlay {
                        fieldShape.strokeBorder(isTitleFocused ? accent.opacity(0.65) : fieldBorder)
                            .allowsHitTesting(false)
                    }
                    .focused($isTitleFocused)
                    .onSubmit(save)
                    .disabled(isSaving)
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Content")
                SimpleLineNumberView(
                    text: $content,
                    font: fontManager.editorFont,
                    isEditable: !isSaving,
                    onDoubleClick: nil,
                    onEscape: cancel,
                    textColor: .textColor,
                    rulerBackgroundColor: rulerFill,
                    onScrollChange: nil
                )
                .accessibilityLabel(Text("Content"))
                .frame(height: height)
                .background(fieldFill, in: fieldShape)
                .clipShape(fieldShape)
                .overlay { fieldShape.strokeBorder(fieldBorder).allowsHitTesting(false) }

                if item.richText != nil, editedContent != nil {
                    Text("Content changes are saved as plain text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            categoryPicker(for: item)
            Divider()
            metadata(for: item)
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.subheadline.weight(.semibold))
    }

    private func metadata(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Item metadata")
            VStack(alignment: .leading, spacing: 7) {
                if let sourceApp = HistoryItemPreviewContent.visibleSourceApp(for: item) {
                    metadataRow("Source") {
                        Text(verbatim: sourceApp).help(sourceApp)
                    }
                }
                if let windowTitle = HistoryItemPreviewContent.visibleWindowTitle(for: item) {
                    metadataRow("Source window") {
                        Text(verbatim: windowTitle).help(windowTitle)
                    }
                }
                if let url = item.metadata?.sourceWebURL {
                    metadataRow("Source Link") {
                        HistorySourceLink(url: url, maxLines: nil)
                    }
                }
                if editingItemID != nil, let createdAt = item.metadata?.createdAt {
                    metadataRow("Registered") {
                        metadataDate(createdAt)
                    }
                }
                if editingItemID != nil {
                    metadataRow("Copied at") {
                        metadataDate(item.timestamp)
                    }
                }
                metadataRow("Character count") {
                    Text(content.count, format: .number)
                }
            }
            .font(.callout)
            .monospacedDigit()
        }
    }

    private func metadataRow<Value: View>(
        _ key: LocalizedStringKey, @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 104, alignment: .leading)
            value()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadataDate(_ date: Date) -> some View {
        Text(date, format: .dateTime.month(.defaultDigits).day().hour(.twoDigits(amPM: .abbreviated)).minute())
            .help(date.formatted(.dateTime.locale(appSettings.appLocale)))
    }

    private func categoryPicker(for item: ClipItem) -> some View {
        let currentSelection = editedContent.map { item.categoryIDs(forDraftContent: $0) } ?? item.categoryIDs
        let initialSelection = originalItem.categoryIDs
        let categories = categoryStore.assignable()
        let ordered = categories.filter { initialSelection.contains($0.id) }
            + categories.filter { !initialSelection.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Categories")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], alignment: .leading, spacing: 4) {
                ForEach(ordered) { category in
                    let isInitiallySelected = currentSelection.contains(category.id)
                    Toggle(isOn: Binding(
                        get: { categoryChanges[category.id] ?? isInitiallySelected },
                        set: { enabled in categoryChanges[category.id] = enabled == isInitiallySelected ? nil : enabled }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: categoryStore.iconName(for: category))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            Text(verbatim: category.name).lineLimit(2)
                        }
                        .help(category.name)
                    }
                    .toggleStyle(ClipEditorCheckboxStyle(tint: accent, fill: fieldFill, border: fieldBorder))
                }
            }
            .padding(2)
        }
        .disabled(isSaving)
    }

    private func cancel() {
        guard !isSaving else { return }
        onClose()
    }

    private func save() {
        guard canSave else { return }
        let changes = categoryChanges
        let title = editedTitle
        let content = editedContent
        isSaving = true
        onSavingChanged(true)
        errorMessage = nil
        Task {
            defer {
                isSaving = false
                onSavingChanged(false)
            }
            do {
                if let editingItemID {
                    try await adapter.updateDetails(
                        itemID: editingItemID, title: title, content: content, categoryChanges: changes
                    )
                } else {
                    try await adapter.createHistoryItem(title: title, content: content ?? "", categoryChanges: changes)
                }
                onClose()
            } catch {
                if case .categoryUnavailable = error as? ClipItemEditError {
                    let availableIDs = Set(categoryStore.assignable().map(\.id))
                    categoryChanges = categoryChanges.filter { availableIDs.contains($0.key) }
                }
                errorMessage = LocalizedStringKey(clipItemEditErrorMessage(error))
            }
        }
    }
}

func clipItemEditErrorMessage(_ error: Error) -> String {
    switch error as? ClipItemEditError {
    case .itemUnavailable: "Item unavailable"
    case .invalidTitle: "Enter a title of up to 120 characters."
    case .emptyContent: "Enter some content."
    case .duplicateContent: "Another history item already has this content."
    case .categoryUnavailable: "A selected category is no longer available."
    case .richTextLossRequiresConfirmation: "Saving will remove formatting. Select Save to continue."
    case nil: "Could not save the item. Please try again."
    }
}

struct ClipEditorButtonStyle: ButtonStyle {
    static let accent = Color(red: 0.09, green: 0.40, blue: 0.37)

    let fill: Color
    let foreground: Color
    let border: Color
    var horizontalPadding: CGFloat = 12
    var height: CGFloat = 32
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: KippleGlassMetrics.inputCornerRadius)
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(border).allowsHitTesting(false))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
    }
}

private struct ClipEditorCheckboxStyle: ToggleStyle {
    let tint: Color
    let fill: Color
    let border: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                let shape = RoundedRectangle(cornerRadius: 4)
                shape
                    .fill(configuration.isOn ? tint : fill)
                    .overlay(shape.strokeBorder(configuration.isOn ? .clear : border))
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                configuration.label
                Spacer(minLength: 0)
            }
            .frame(minHeight: 23)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
        }
    }
}
