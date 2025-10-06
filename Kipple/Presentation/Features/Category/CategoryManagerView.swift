//
//  CategoryManagerView.swift
//  Kipple
//
//  シンプルなカテゴリ管理UI：追加/リネーム/削除。
//

import SwiftUI

private enum CategoryManagerLayout {
    static let columnSpacing: CGFloat = 8
    static let iconColumnWidth: CGFloat = 36
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

struct CategoryManagerView: View {
    @ObservedObject private var store = UserCategoryStore.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var symbol: String = UserCategoryStore.availableSymbols.first ?? "tag"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Categories").font(.headline)

            // 各カテゴリ列にフィルタ表示チェックを配置（設定から移動）

            HStack(spacing: CategoryManagerLayout.columnSpacing) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth)

                Picker("Icon", selection: $symbol) {
                    ForEach(UserCategoryStore.availableSymbols, id: \.self) { s in
                        Label(s, systemImage: s).labelStyle(.iconOnly)
                            .tag(s)
                    }
                }
                .pickerStyle(.menu)

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
                        .frame(width: CategoryManagerLayout.iconColumnWidth, alignment: .leading)
                    Text("Name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth, alignment: .leading)
                    Spacer(minLength: CategoryManagerLayout.spacerMinWidth)
                    Text("Show in filter")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: CategoryManagerLayout.toggleColumnWidth, alignment: .center)
                    Text("Delete")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: CategoryManagerLayout.deleteColumnWidth, alignment: .center)
                }
                .padding(.vertical, 4)

                ForEach(store.all()) { category in
                    HStack(spacing: CategoryManagerLayout.columnSpacing) {
                        iconSelector(for: category)
                            .frame(width: CategoryManagerLayout.iconColumnWidth, alignment: .leading)
                        TextField("Name", text: Binding(
                            get: { category.name },
                            set: { store.rename(id: category.id, to: $0) }
                        ))
                        .disabled(store.isBuiltIn(category.id))
                        .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth, alignment: .leading)
                        Spacer(minLength: CategoryManagerLayout.spacerMinWidth)
                        Toggle("Show in filter", isOn: filterBinding(for: category))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .frame(width: CategoryManagerLayout.toggleColumnWidth, alignment: .center)
                            .disabled(store.isBuiltIn(category.id))

                        if !store.isBuiltIn(category.id) {
                            Button(
                                role: .destructive,
                                action: { deleteCategoryAndReassign(category) },
                                label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(width: CategoryManagerLayout.deleteColumnWidth, height: 24)
                                }
                            )
                            .buttonStyle(.borderless)
                            .help("Delete category")
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.3))
                                .frame(width: CategoryManagerLayout.deleteColumnWidth, height: 24)
                        }
                    }
                    .contextMenu {
                        if !store.isBuiltIn(category.id) {
                            Menu("Change Icon") {
                                ForEach(UserCategoryStore.availableSymbols, id: \.self) { s in
                                    Button(
                                        action: { store.changeIcon(id: category.id, to: s) },
                                        label: {
                                            Label(s, systemImage: s).labelStyle(.titleAndIcon)
                                        }
                                    )
                                }
                            }
                            Button("Delete", role: .destructive) {
                                deleteCategoryAndReassign(category)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !store.isBuiltIn(category.id) {
                            Button(role: .destructive) {
                                deleteCategoryAndReassign(category)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let cat = store.all()[index]
                        if !store.isBuiltIn(cat.id) {
                            deleteCategoryAndReassign(cat)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
            }
        }
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
        } else {
            Menu {
                ForEach(UserCategoryStore.availableSymbols, id: \.self) { symbol in
                    Button {
                        store.changeIcon(id: category.id, to: symbol)
                    } label: {
                        Label(symbol, systemImage: symbol)
                    }
                }
            } label: {
                Image(systemName: store.iconName(for: category))
                    .frame(width: 24, height: 24)
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("アイコンを変更")
        }
    }

    func filterBinding(for category: UserCategory) -> Binding<Bool> {
        if let kind = store.builtInKind(for: category.id) {
            switch kind {
            case .url:
                return $appSettings.filterCategoryURL
            case .none:
                return $appSettings.filterCategoryNone
            }
        }
        return Binding(
            get: { category.isFilterEnabled },
            set: { store.setFilterEnabled(id: category.id, $0) }
        )
    }

    func deleteCategoryAndReassign(_ category: UserCategory) {
        let targetId = category.id
        let noneId = store.noneCategoryId()
        let adapter = ModernClipboardServiceAdapter.shared
        Task { @MainActor in
            let items = adapter.history.filter { $0.userCategoryId == targetId }
            for var item in items {
                item.userCategoryId = noneId
                await adapter.updateItem(item)
            }
            store.remove(id: targetId)
        }
    }
}

extension CategoryManagerView {
    static var minimumWidth: CGFloat { CategoryManagerLayout.minimumWidth }
    static var minimumHeight: CGFloat { CategoryManagerLayout.minimumHeight }
}
