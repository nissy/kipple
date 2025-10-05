//
//  CategoryManagerView.swift
//  Kipple
//
//  シンプルなカテゴリ管理UI：追加/リネーム/削除。
//

import SwiftUI

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

            let toggleColumnWidth: CGFloat = 140
            let deleteColumnWidth: CGFloat = 40

            HStack(spacing: 8) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)

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
                HStack(spacing: 8) {
                    Color.clear.frame(width: 24, height: 1)
                    Text("Name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Show in filter")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: toggleColumnWidth, alignment: .center)
                    Text("Delete")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: deleteColumnWidth, alignment: .center)
                }
                .padding(.vertical, 4)

                ForEach(store.all()) { category in
                    HStack(spacing: 8) {
                        Image(systemName: store.iconName(for: category))
                            .frame(width: 24)
                            .font(.system(size: 14))
                        TextField("Name", text: Binding(
                            get: { category.name },
                            set: { store.rename(id: category.id, to: $0) }
                        ))
                        .disabled(store.isBuiltIn(category.id))
                        Spacer()
                        Toggle("Show in filter", isOn: filterBinding(for: category))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .frame(width: toggleColumnWidth, alignment: .center)
                            .disabled(store.isBuiltIn(category.id))

                        if !store.isBuiltIn(category.id) {
                            Button(role: .destructive) {
                                deleteCategoryAndReassign(category)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: deleteColumnWidth, height: 24)
                            }
                            .buttonStyle(.borderless)
                            .help("Delete category")
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.3))
                                .frame(width: deleteColumnWidth, height: 24)
                        }
                    }
                    .contextMenu {
                        if !store.isBuiltIn(category.id) {
                            Menu("Change Icon") {
                                ForEach(UserCategoryStore.availableSymbols, id: \.self) { s in
                                    Button(action: { store.changeIcon(id: category.id, to: s) }) {
                                        Label(s, systemImage: s).labelStyle(.titleAndIcon)
                                    }
                                }
                            }
                            Button("Delete", role: .destructive) { deleteCategoryAndReassign(category) }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !store.isBuiltIn(category.id) {
                            Button(role: .destructive) { deleteCategoryAndReassign(category) } label: {
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
        .frame(minWidth: 460, minHeight: 520)
    }
}

// MARK: - Helpers
private extension CategoryManagerView {
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
