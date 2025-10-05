//
//  UserCategoryStore.swift
//  Kipple
//
//  ユーザ定義カテゴリの永続化と公開。UserDefaults にJSON保存。
//

import Foundation
import Combine

@MainActor
final class UserCategoryStore: ObservableObject {
    static let shared = UserCategoryStore()

    @Published private(set) var categories: [UserCategory] = [] {
        didSet { persist() }
    }

    private let storageKey = "userCategories.v1"

    // 単色かつテキスト関連の推奨シンボル一覧
    static let allowedSymbols: [String] = [
        "doc.text", "doc", "text.quote", "pencil", "square.and.pencil",
        "list.bullet", "list.number", "text.alignleft", "text.justify",
        "paperclip", "tag", "at", "link", "doc.on.clipboard",
        "curlybraces", "angle.brackets"
    ]

    // ビルトインカテゴリ（削除不可）
    private static let builtInNone = UserCategory(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        name: "None",
        iconSystemName: "tag",
        isFilterEnabled: true
    )
    private static let builtInURL = UserCategory(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "URL",
        iconSystemName: "link",
        isFilterEnabled: true
    )
    private static var builtIns: [UserCategory] { [builtInNone, builtInURL] }

    func noneCategory() -> UserCategory { Self.builtInNone }
    func noneCategoryId() -> UUID { Self.builtInNone.id }

    enum BuiltInKind { case none, url }
    func builtInKind(for id: UUID) -> BuiltInKind? {
        if id == Self.builtInNone.id { return .none }
        if id == Self.builtInURL.id { return .url }
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
        return categories.first { $0.id == id }
    }

    func add(name: String, iconSystemName: String) {
        let symbol = UserCategoryStore.allowedSymbols.contains(iconSystemName)
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
        categories[index].iconSystemName = UserCategoryStore.allowedSymbols.contains(systemName) ? systemName : categories[index].iconSystemName
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
            categories = try JSONDecoder().decode([UserCategory].self, from: data)
        } catch {
            Logger.shared.error("Failed to load categories: \(error)")
            categories = []
        }
    }
}
