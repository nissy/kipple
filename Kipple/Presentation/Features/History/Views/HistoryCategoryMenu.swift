import SwiftUI

struct HistoryCategoryMenu: View {
    let item: ClipItem
    let isSelected: Bool
    let onChangeCategory: ((UUID?) -> Void)?
    let onOpenCategoryManager: (() -> Void)?

    private let store = UserCategoryStore.shared
    @State private var isHovered = false

    var body: some View {
        Menu(content: menuContent) {
            menuLabel
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(
            width: KippleButtonMetrics.historyCategoryButtonSize,
            height: KippleButtonMetrics.historyCategoryButtonSize
        )
        .background(categoryAffordance)
        .contentShape(Circle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private func menuContent() -> some View {
        let currentUserCategoryId = item.userCategoryId
        let noneCategory = store.noneCategory()
        let noneId = store.noneCategoryId()
        let isNoneSelected =
            (currentUserCategoryId == nil && item.category != .url) ||
            currentUserCategoryId == noneId
        Button {
            onChangeCategory?(noneId)
        } label: {
            categoryMenuRow(
                name: noneCategory.name,
                systemImage: store.iconName(for: noneCategory),
                selected: isNoneSelected
            )
        }

        let urlCategory = store.urlCategory()
        let urlId = store.urlCategoryId()
        let isURLSelected =
            (currentUserCategoryId == nil && item.category == .url) ||
            currentUserCategoryId == urlId
        Button {
            onChangeCategory?(urlId)
        } label: {
            categoryMenuRow(
                name: urlCategory.name,
                systemImage: store.iconName(for: urlCategory),
                selected: isURLSelected
            )
        }

        let userDefinedCategories = store.userDefined()
        if !userDefinedCategories.isEmpty {
            Divider()
            ForEach(userDefinedCategories) { cat in
                Button {
                    onChangeCategory?(cat.id)
                } label: {
                    categoryMenuRow(
                        name: cat.name,
                        systemImage: store.iconName(for: cat),
                        selected: item.userCategoryId == cat.id
                    )
                }
            }
        }

        if onOpenCategoryManager != nil {
            Divider()
            Button("Manage Categories…") {
                onOpenCategoryManager?()
            }
        }
    }

    private var menuLabel: some View {
        let current = store.category(id: item.userCategoryId)
        let iconName = current.map { store.iconName(for: $0) } ?? item.category.icon
        return ZStack {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(categoryIconForeground)
                .frame(
                    width: KippleButtonMetrics.historyCategoryIconSize,
                    height: KippleButtonMetrics.historyCategoryIconSize
                )
        }
        .frame(
            width: KippleButtonMetrics.historyCategoryButtonSize,
            height: KippleButtonMetrics.historyCategoryButtonSize
        )
        .contentShape(Circle())
    }

    private var categoryAffordance: some View {
        Circle()
            .fill(
                isSelected || isHovered
                ? KippleButtonAppearance.inactivePillFill
                : Color.clear
            )
    }

    private var categoryIconForeground: Color {
        isSelected ? .primary : KippleButtonAppearance.inactiveForeground
    }

    private func categoryMenuRow(name: String, systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(KippleButtonAppearance.inactiveForeground)
            Text(verbatim: name)
                .font(.system(size: 12))
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.vertical, 2)
    }
}
