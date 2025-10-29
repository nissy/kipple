//
//  UserCategoryStore.swift
//  Kipple
//
//  ユーザ定義カテゴリの永続化と公開。UserDefaults にJSON保存。
//

import Foundation
import Combine
import AppKit

@MainActor
final class UserCategoryStore: ObservableObject {
    static let shared = UserCategoryStore()

    @Published private(set) var categories: [UserCategory] = [] {
        didSet { persist() }
    }

    private let storageKey = "userCategories.v1"

    // 単色かつテキスト関連の推奨シンボル一覧
    static let allowedSymbols: [String] = [
        // Documents & text
        "doc.text", "doc", "doc.richtext", "doc.append",
        "text.quote", "text.alignleft", "text.aligncenter", "text.alignright",
        "text.justify", "textformat", "textformat.size", "textformat.abc",
        "text.badge.plus",

        // Editing & annotations
        "pencil", "pencil.circle", "square.and.pencil", "highlighter",
        "paintbrush", "scribble", "lasso", "magicwand", "rectangle.and.pencil.and.ellipsis",

        // Lists & organization
        "list.bullet", "list.bullet.rectangle", "list.number", "list.triangle",
        "checklist", "calendar", "calendar.badge.clock", "clock",
        "bookmark", "bookmark.fill",

        // Communication & references
        "paperclip", "tray.and.arrow.down", "envelope", "at", "number",
        "link", "link.badge.plus", "doc.on.clipboard", "quote.bubble",
        "bubble.left.and.bubble.right",

        // Code & markup
        "curlybraces", "curlybraces.square", "angle.brackets", "angle.bracket.square",
        "chevron.left.slash.chevron.right", "terminal", "text.cursor", "keyboard",
        "command", "rectangle.and.text.magnifyingglass",

        // Tags & metadata
        "tag", "tag.circle", "folder", "folder.badge.plus", "rectangle.stack",
        "archivebox", "tray.full", "magnifyingglass", "magnifyingglass.circle", "pin",

        // Symbols for notes and emphasis
        "star", "star.circle", "flag", "flag.checkered", "bookmark.circle",
        "lightbulb", "bolt", "exclamationmark.circle", "info.circle", "questionmark.circle",

        // Shapes useful for categorization
        "circle", "square", "triangle", "diamond", "octagon",
        "circle.grid.2x2", "square.grid.3x3", "rhombus", "shield"
    ]

    static let availableSymbols: [String] = {
        allowedSymbols.filter { symbol in
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        }
    }()

    // ビルトインカテゴリ（削除不可）
    private static let builtInNoneID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private static let builtInURLID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static var builtInNone: UserCategory {
        UserCategory(
            id: builtInNoneID,
            name: "None",
            iconSystemName: "tag",
            isFilterEnabled: false
        )
    }
    private static var builtInURL: UserCategory {
        UserCategory(
            id: builtInURLID,
            name: "URL",
            iconSystemName: "link",
            isFilterEnabled: true
        )
    }
    private static var builtIns: [UserCategory] { [builtInNone, builtInURL] }

    func noneCategory() -> UserCategory { Self.builtInNone }
    func noneCategoryId() -> UUID { Self.builtInNoneID }

    enum BuiltInKind { case none, url }
    func builtInKind(for id: UUID) -> BuiltInKind? {
        if id == Self.builtInNoneID { return .none }
        if id == Self.builtInURLID { return .url }
        return nil
    }

    private init() { load() }

    /// すべて（ビルトイン＋ユーザ定義）
    func all() -> [UserCategory] { Self.builtIns + categories }

    /// ユーザ定義のみ
    func userDefined() -> [UserCategory] { categories }

    /// フィルタ有効なユーザ定義のみ
    func userDefinedFilters() -> [UserCategory] { categories.filter { $0.isFilterEnabled } }

    func isBuiltIn(_ id: UUID) -> Bool { Self.builtIns.contains { $0.id == id } }

    func category(id: UUID?) -> UserCategory? {
        guard let id else { return nil }
        if let builtin = Self.builtIns.first(where: { $0.id == id }) {
            return builtin
        }
        return categories.first { $0.id == id }
    }

    func iconName(for category: UserCategory) -> String {
        Self.resolvedIconName(category.iconSystemName)
    }

    func add(name: String, iconSystemName: String) {
        let symbol = UserCategoryStore.availableSymbols.contains(iconSystemName)
            ? iconSystemName : "tag"
        let new = UserCategory(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                               iconSystemName: symbol,
                               isFilterEnabled: true)
        categories.append(new)
    }

    func remove(id: UUID) {
        guard !isBuiltIn(id) else { return }
        categories.removeAll { $0.id == id }
    }

    func rename(id: UUID, to name: String) {
        guard !isBuiltIn(id), let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
    }

    func changeIcon(id: UUID, to systemName: String) {
        guard !isBuiltIn(id), let index = categories.firstIndex(where: { $0.id == id }) else { return }
        if UserCategoryStore.availableSymbols.contains(systemName) {
            categories[index].iconSystemName = systemName
        }
    }

    func setFilterEnabled(id: UUID, _ enabled: Bool) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].isFilterEnabled = enabled
    }

    // MARK: - Persistence
    private func persist() {
        do {
            let data = try JSONEncoder().encode(categories)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Logger.shared.error("Failed to save categories: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            categories = []
            return
        }
        do {
            categories = try JSONDecoder().decode([UserCategory].self, from: data).map { category in
                var updated = category
                if Self.resolvedIconName(category.iconSystemName) != category.iconSystemName {
                    updated.iconSystemName = "tag"
                }
                return updated
            }
        } catch {
            Logger.shared.error("Failed to load categories: \(error)")
            categories = []
        }
    }

    private static func resolvedIconName(_ symbol: String) -> String {
        if availableSymbols.contains(symbol) {
            return symbol
        }
        if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
            return symbol
        }
        return "tag"
    }
}
