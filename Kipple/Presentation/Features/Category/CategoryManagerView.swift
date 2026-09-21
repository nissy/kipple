//
//  CategoryManagerView.swift
//  Kipple
//
//  シンプルなカテゴリ管理UI：追加/リネーム/削除。
//

import SwiftUI

private enum CategoryManagerLayout {
    static let columnSpacing: CGFloat = 8
    static let iconColumnWidth: CGFloat = 56
    static let nameColumnMinWidth: CGFloat = 180
    static let toggleColumnWidth: CGFloat = 140
    static let deleteColumnWidth: CGFloat = 40
    static let spacerMinWidth: CGFloat = 12
    static let listHorizontalPadding: CGFloat = 32
    static let minimumHeight: CGFloat = 520

    static var minimumWidth: CGFloat {
        let columns = iconColumnWidth + nameColumnMinWidth + toggleColumnWidth + deleteColumnWidth
        let spacing = spacerMinWidth + columnSpacing * 4 + listHorizontalPadding * 2
        return max(420, columns + spacing)
    }
}

private enum CategoryManagerAppearance {
    static let builtInColor = Color.secondary
}

struct CategoryManagerView: View {
    @ObservedObject private var store = UserCategoryStore.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var deletionError = false
    @State private var isDeleting = false
    @State private var name: String = ""
    @State private var symbol: String = UserCategoryStore.availableSymbols.first ?? "tag"

    var body: some View {
        content
            .environment(\.locale, appSettings.appLocale)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Categories").font(.headline)

            Text("URL, OCR and AI are automatic categories. You can change them on each item.")
                .font(.caption).foregroundStyle(.secondary)
            Text("AI is added to items received through MCP.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Deleting a category keeps the history and its other categories.")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: CategoryManagerLayout.columnSpacing) {
                TextField("Name", text: $name)
                    .textFieldStyle(.bordered)
                    .textInputBorderShape(.roundedRectangle)
                    .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth)

                Menu {
                    ForEach(UserCategoryStore.availableSymbols, id: \.self) { s in
                        Button {
                            symbol = s
                        } label: {
                            Label(s, systemImage: s)
                                .labelStyle(.titleAndIcon)
                                .accessibilityLabel(Text(s))
                        }
                    }
                } label: {
                    Image(systemName: symbol)
                        .frame(width: 24, height: 24)
                        .font(.system(size: 14))
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(Text("Choose icon"))

                Button("Add") {
                    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    store.add(name: name, iconSystemName: symbol)
                    name = ""
                }
                .keyboardShortcut(.return)
            }

            Divider()

            List {
                HStack(spacing: CategoryManagerLayout.columnSpacing) {
                    Text("Icon")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: CategoryManagerLayout.iconColumnWidth, alignment: .leading)
                    Text("Name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth, alignment: .leading)
                    Spacer(minLength: CategoryManagerLayout.spacerMinWidth)
                    Text("Show in filter")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: CategoryManagerLayout.toggleColumnWidth, alignment: .center)
                    Text("Delete")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: CategoryManagerLayout.deleteColumnWidth, alignment: .center)
                }
                .padding(.vertical, 4)

                ForEach(store.all()) { category in
                    HStack(spacing: CategoryManagerLayout.columnSpacing) {
                        iconSelector(for: category)
                            .frame(width: CategoryManagerLayout.iconColumnWidth, alignment: .leading)
                        let isBuiltIn = store.isBuiltIn(category.id)
                        if isBuiltIn {
                            Text(category.name)
                                .foregroundColor(CategoryManagerAppearance.builtInColor)
                                .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth, alignment: .leading)
                        } else {
                            TextField("Name", text: Binding(
                                get: { category.name },
                                set: { store.rename(id: category.id, to: $0) }
                            ))
                            .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth, alignment: .leading)
                        }
                        Spacer(minLength: CategoryManagerLayout.spacerMinWidth)
                        Toggle("Show in filter", isOn: filterBinding(for: category))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .frame(width: CategoryManagerLayout.toggleColumnWidth, alignment: .center)

                        if !isBuiltIn {
                            Button(
                                role: .destructive,
                                action: { deleteCategories([category]) },
                                label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(width: CategoryManagerLayout.deleteColumnWidth, height: 24)
                                }
                            )
                            .buttonStyle(.borderless)
                            .help(Text("Delete category"))
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(CategoryManagerAppearance.builtInColor)
                                .frame(width: CategoryManagerLayout.deleteColumnWidth, height: 24)
                                .help(Text("Built-in categories cannot be deleted"))
                        }
                    }
                    .contextMenu {
                        if !store.isBuiltIn(category.id) {
                            Menu("Change Icon") {
                                ForEach(UserCategoryStore.availableSymbols, id: \.self) { s in
                                    Button(
                                        action: { store.changeIcon(id: category.id, to: s) },
                                        label: {
                                            Label(s, systemImage: s)
                                                .labelStyle(.titleAndIcon)
                                                .accessibilityLabel(Text(s))
                                        }
                                    )
                                }
                            }
                            Button("Delete", role: .destructive) {
                                deleteCategories([category])
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !store.isBuiltIn(category.id) {
                            Button(role: .destructive) {
                                deleteCategories([category])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    let categories = indexSet.map { store.all()[$0] }.filter { !store.isBuiltIn($0.id) }
                    deleteCategories(categories)
                }
            }

            if deletionError {
                Text("Could not delete the category. Please try again.").foregroundStyle(.red).font(.caption)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .disabled(isDeleting)
        .padding(16)
        .frame(minWidth: CategoryManagerView.minimumWidth, minHeight: CategoryManagerLayout.minimumHeight)
    }
}

// MARK: - Helpers
private extension CategoryManagerView {
    @ViewBuilder
    func iconSelector(for category: UserCategory) -> some View {
        if store.isBuiltIn(category.id) {
            Image(systemName: store.iconName(for: category))
                .frame(width: 24, height: 24)
                .font(.system(size: 14))
                .foregroundColor(CategoryManagerAppearance.builtInColor)
        } else {
            Menu {
                ForEach(UserCategoryStore.availableSymbols, id: \.self) { symbol in
                    Button {
                        store.changeIcon(id: category.id, to: symbol)
                    } label: {
                        Label(symbol, systemImage: symbol)
                            .labelStyle(.iconOnly)
                            .accessibilityLabel(Text(symbol))
                    }
                }
            } label: {
                Image(systemName: store.iconName(for: category))
                    .frame(width: 24, height: 24)
                    .font(.system(size: 14))
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(Text("Change icon"))
        }
    }

    func filterBinding(for category: UserCategory) -> Binding<Bool> {
        if let kind = store.builtInKind(for: category.id) {
            switch kind {
            case .url:
                return Binding(
                    get: { appSettings.filterCategoryURL },
                    set: { appSettings.filterCategoryURL = $0 }
                )
            case .ocr:
                return Binding(get: { appSettings.filterCategoryOCR }, set: { appSettings.filterCategoryOCR = $0 })
            case .ai:
                return Binding(get: { appSettings.filterCategoryAI }, set: { appSettings.filterCategoryAI = $0 })
            case .none:
                return Binding(
                    get: { appSettings.filterCategoryNone },
                    set: { appSettings.filterCategoryNone = $0 }
                )
            }
        }
        return Binding(
            get: { category.isFilterEnabled },
            set: { store.setFilterEnabled(id: category.id, $0) }
        )
    }

    func deleteCategories(_ categories: [UserCategory]) {
        guard !isDeleting else { return }
        isDeleting = true
        deletionError = false
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                for category in categories {
                    try await ModernClipboardServiceAdapter.shared.removeCategoryDefinition(category.id)
                    store.remove(id: category.id)
                }
            } catch {
                deletionError = true
            }
        }
    }
}

extension CategoryManagerView {
    static var minimumWidth: CGFloat { CategoryManagerLayout.minimumWidth }
    static var minimumHeight: CGFloat { CategoryManagerLayout.minimumHeight }
}
