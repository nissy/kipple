import SwiftUI

struct CategoryPopoverAction {
    var handler: @MainActor (UUID?, Bool) -> Void

    @MainActor func callAsFunction(_ id: UUID?, _ presented: Bool) { handler(id, presented) }
}

extension EnvironmentValues {
    @Entry var categoryPopoverChanged = CategoryPopoverAction { _, _ in }
}

struct HistoryCategoryMenu: View {
    let item: ClipItem
    let isSelected: Bool
    let onChangeCategory: ((ClipCategoryChange) async throws -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    var showsTitle = false
    @ObservedObject private var store = UserCategoryStore.shared
    @Environment(\.categoryPopoverChanged) private var presentationChanged
    @State private var isPresented = false
    @State private var isSaving = false
    @State private var saveError = false

    var body: some View {
        let categories = store.categories(for: item)
        Button {
            presentationChanged(item.id, true)
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.iconName(for: categories))
                    .font(.system(size: 12, weight: .medium))
                    .overlay(alignment: .bottomTrailing) {
                        if categories.count > 1 {
                            let countLabel = Text("\(categories.count)")
                                .font(.system(size: 8, weight: .bold))
                                .fixedSize()
                            if categories.count < 10 {
                                countLabel.frame(width: 0, alignment: .leading).offset(x: 1, y: 2)
                            } else {
                                countLabel.offset(y: 8)
                            }
                        }
                    }
                    .frame(
                        width: showsTitle ? 20 : MainViewMetrics.HistoryColumns.rowCategoryWidth,
                        height: MainViewMetrics.HistoryColumns.controlColumnWidth
                    )
                if showsTitle {
                    Text("Categories")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .fixedSize()
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .accessibilityLabel(Text("Edit categories"))
        .accessibilityValue(Text(verbatim: categoryNames(categories)))
        .help(categoryNames(categories))
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit categories").font(.headline)
                Text("Select multiple categories. Automatic categories can also be removed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.assignable()) { category in
                            Toggle(isOn: Binding(
                                get: { item.categoryIDs.contains(category.id) },
                                set: { enabled in update(.set(category.id, enabled: enabled)) }
                            )) {
                                Label(category.name, systemImage: store.iconName(for: category))
                            }
                            .toggleStyle(.checkbox)
                            .disabled(isSaving || onChangeCategory == nil)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
                }.frame(maxHeight: 280)
                if saveError {
                    Text("Could not save categories. Please try again.").font(.caption).foregroundStyle(.red)
                }
                Divider()
                HStack {
                    Button("Manage Categories…") {
                        onOpenCategoryManager?()
                        isPresented = false
                    }
                    Spacer()
                    Button("Clear") { update(.clear) }
                        .disabled(item.categoryIDs.isEmpty || isSaving || onChangeCategory == nil)
                }
            }.padding(16).frame(width: 300)
        }
        .onChange(of: isPresented) { _, presented in
            if !presented { presentationChanged(item.id, false) }
        }
        .onDisappear { if isPresented { presentationChanged(item.id, false) } }
    }

    private func update(_ change: ClipCategoryChange) {
        guard let onChangeCategory, !isSaving else { return }
        isSaving = true
        saveError = false
        Task { @MainActor in
            defer { isSaving = false }
            do { try await onChangeCategory(change) } catch { saveError = true }
        }
    }

    private func categoryNames(_ categories: [UserCategory]) -> String {
        categories.isEmpty ? store.noneCategory().name : categories.map(\.name).joined(separator: ", ")
    }
}
