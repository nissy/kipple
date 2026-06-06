//
//  CategoryManagerView.swift
//  Kipple
//
//  シンプルなカテゴリ管理UI：追加/リネーム/削除。
//

import SwiftUI

private enum CategoryManagerLayout {
    static let columnSpacing: CGFloat = 8
    static let iconColumnWidth: CGFloat = 48
    static let nameColumnMinWidth: CGFloat = 180
    static let toggleColumnWidth: CGFloat = 140
    static let deleteColumnWidth: CGFloat = 40
    static let spacerMinWidth: CGFloat = 12
    static let listHorizontalPadding: CGFloat = 32
    static let minimumHeight: CGFloat = 520
    static let contentSpacing: CGFloat = 12
    static let contentHorizontalPadding: CGFloat = 16
    static let contentTopPadding: CGFloat = 36
    static let contentBottomPadding: CGFloat = 16
    static let addInputHorizontalPadding: CGFloat = 10
    static let addInputVerticalPadding: CGFloat = 6
    static let tableRowSpacing: CGFloat = 4
    static let tablePadding: CGFloat = 8
    static let tableHeaderHorizontalPadding: CGFloat = 4
    static let tableHeaderVerticalPadding: CGFloat = 6
    static let tableRowHorizontalPadding: CGFloat = 4
    static let tableRowVerticalPadding: CGFloat = 3
    static let rowInputHorizontalPadding: CGFloat = 8
    static let rowInputVerticalPadding: CGFloat = 5
    static let headerFontSize: CGFloat = 11
    static let iconFontSize: CGFloat = 14
    static let deleteIconFontSize: CGFloat = 12

    static var minimumWidth: CGFloat {
        let columns = iconColumnWidth + nameColumnMinWidth + toggleColumnWidth + deleteColumnWidth
        let spacing = spacerMinWidth + columnSpacing * 4 + listHorizontalPadding * 2
        return max(420, columns + spacing)
    }
}

private enum CategoryManagerAppearance {
    static let builtInColor = KippleButtonAppearance.inactiveForeground.opacity(0.55)
}

struct CategoryManagerView: View {
    @ObservedObject private var store = UserCategoryStore.shared
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var name: String = ""
    @State private var symbol: String = UserCategoryStore.availableSymbols.first ?? "tag"

    let onClose: () -> Void

    init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    var body: some View {
        content
            .environment(\.locale, appSettings.appLocale)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CategoryManagerLayout.contentSpacing) {
            Text("Manage Categories").font(.headline)

            // 各カテゴリ列にフィルタ表示チェックを配置（設定から移動）

            HStack(spacing: CategoryManagerLayout.columnSpacing) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, CategoryManagerLayout.addInputHorizontalPadding)
                    .padding(.vertical, CategoryManagerLayout.addInputVerticalPadding)
                    .background(inputSurface(cornerRadius: KippleGlassMetrics.inputCornerRadius))
                    .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth)

                Picker("Icon", selection: $symbol) {
                    ForEach(UserCategoryStore.availableSymbols, id: \.self) { s in
                        Label(s, systemImage: s).labelStyle(.iconOnly)
                            .tag(s)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)

                Button("Add") {
                    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    store.add(name: name, iconSystemName: symbol)
                    name = ""
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Divider()

            categoryTable

            HStack {
                Spacer()
                Button("Close") { onClose() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, CategoryManagerLayout.contentHorizontalPadding)
        .padding(.top, CategoryManagerLayout.contentTopPadding)
        .padding(.bottom, CategoryManagerLayout.contentBottomPadding)
        .frame(minWidth: CategoryManagerView.minimumWidth, minHeight: CategoryManagerLayout.minimumHeight)
        .background(Color.clear)
    }
}

// MARK: - Helpers
private extension CategoryManagerView {
    var categoryTable: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CategoryManagerLayout.tableRowSpacing) {
                categoryHeader

                ForEach(store.all()) { category in
                    categoryRow(category)
                }
            }
            .padding(CategoryManagerLayout.tablePadding)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: KippleGlassMetrics.panelCornerRadius, style: .continuous)
                .fill(KippleGlassAppearance.subtlePanelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KippleGlassMetrics.panelCornerRadius, style: .continuous)
                .stroke(KippleGlassAppearance.controlStroke, lineWidth: KippleGlassMetrics.controlStrokeWidth)
        )
    }

    var categoryHeader: some View {
        HStack(spacing: CategoryManagerLayout.columnSpacing) {
            Text("Icon")
                .frame(width: CategoryManagerLayout.iconColumnWidth, alignment: .leading)
            Text("Name")
                .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth, alignment: .leading)
            Spacer(minLength: CategoryManagerLayout.spacerMinWidth)
            Text("Show in filter")
                .frame(width: CategoryManagerLayout.toggleColumnWidth, alignment: .center)
            Text("Delete")
                .frame(width: CategoryManagerLayout.deleteColumnWidth, alignment: .center)
        }
        .font(.system(size: CategoryManagerLayout.headerFontSize, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, CategoryManagerLayout.tableHeaderHorizontalPadding)
        .padding(.vertical, CategoryManagerLayout.tableHeaderVerticalPadding)
    }

    func categoryRow(_ category: UserCategory) -> some View {
        let builtInKind = store.builtInKind(for: category.id)
        let isBuiltIn = store.isBuiltIn(category.id)

        return HStack(spacing: CategoryManagerLayout.columnSpacing) {
            iconSelector(for: category)
                .frame(width: CategoryManagerLayout.iconColumnWidth, alignment: .leading)

            categoryNameField(category, isBuiltIn: isBuiltIn)

            Spacer(minLength: CategoryManagerLayout.spacerMinWidth)

            Toggle("Show in filter", isOn: filterBinding(for: category))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: CategoryManagerLayout.toggleColumnWidth, alignment: .center)
                .disabled(builtInKind == .url)

            deleteControl(category, isBuiltIn: isBuiltIn)
        }
        .padding(.horizontal, CategoryManagerLayout.tableRowHorizontalPadding)
        .padding(.vertical, CategoryManagerLayout.tableRowVerticalPadding)
        .contextMenu {
            if !isBuiltIn {
                Menu("Change Icon") {
                    ForEach(UserCategoryStore.availableSymbols, id: \.self) { symbol in
                        Button {
                            store.changeIcon(id: category.id, to: symbol)
                        } label: {
                            Label(symbol, systemImage: symbol)
                                .labelStyle(.iconOnly)
                                .accessibilityLabel(Text(symbol))
                        }
                    }
                }
                Button("Delete", role: .destructive) {
                    deleteCategoryAndReassign(category)
                }
            }
        }
    }

    @ViewBuilder
    func categoryNameField(_ category: UserCategory, isBuiltIn: Bool) -> some View {
        if isBuiltIn {
            Text(category.name)
                .foregroundColor(CategoryManagerAppearance.builtInColor)
                .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth, alignment: .leading)
        } else {
            TextField("Name", text: Binding(
                get: { category.name },
                set: { store.rename(id: category.id, to: $0) }
            ))
            .textFieldStyle(.plain)
            .padding(.horizontal, CategoryManagerLayout.rowInputHorizontalPadding)
            .padding(.vertical, CategoryManagerLayout.rowInputVerticalPadding)
            .background(inputSurface(cornerRadius: KippleGlassMetrics.compactInputCornerRadius))
            .frame(minWidth: CategoryManagerLayout.nameColumnMinWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    func deleteControl(_ category: UserCategory, isBuiltIn: Bool) -> some View {
        if !isBuiltIn {
            Button(
                role: .destructive,
                action: { deleteCategoryAndReassign(category) },
                label: {
                    Image(systemName: "trash")
                        .font(.system(size: CategoryManagerLayout.deleteIconFontSize, weight: .medium))
                        .frame(
                            width: CategoryManagerLayout.deleteColumnWidth,
                            height: KippleButtonMetrics.compactIconSize
                        )
                }
            )
            .buttonStyle(.borderless)
            .help(Text("Delete category"))
        } else {
            Image(systemName: "lock.fill")
                .font(.system(size: CategoryManagerLayout.deleteIconFontSize, weight: .medium))
                .foregroundColor(CategoryManagerAppearance.builtInColor)
                .frame(
                    width: CategoryManagerLayout.deleteColumnWidth,
                    height: KippleButtonMetrics.compactIconSize
                )
                .help(Text("Built-in categories cannot be deleted"))
        }
    }

    func inputSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(KippleGlassAppearance.controlFill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(KippleGlassAppearance.controlStroke, lineWidth: KippleGlassMetrics.controlStrokeWidth)
            )
    }

    @ViewBuilder
    func iconSelector(for category: UserCategory) -> some View {
        if store.isBuiltIn(category.id) {
            Image(systemName: store.iconName(for: category))
                .frame(
                    width: KippleButtonMetrics.compactIconSize,
                    height: KippleButtonMetrics.compactIconSize
                )
                .font(.system(size: CategoryManagerLayout.iconFontSize))
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
                    .frame(
                        width: KippleButtonMetrics.compactIconSize,
                        height: KippleButtonMetrics.compactIconSize
                    )
                    .font(.system(size: CategoryManagerLayout.iconFontSize))
            }
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
