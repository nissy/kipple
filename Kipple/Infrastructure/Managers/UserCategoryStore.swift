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
    @Published private var filterOrder: [UUID]

    private let defaults: UserDefaults
    private let storageKey = "userCategories.v1"
    private static let filterOrderKey = "categoryFilterOrder.v1"

    // カテゴリ編集のアイコンを一覧の表示順で保持する。
    private static let iconSymbols: [String] = [
        "doc.text", "note.text", "doc.on.clipboard", "text.quote", "list.bullet", "doc", "doc.richtext",
        "doc.plaintext", "doc.on.doc", "paperclip", "square.and.pencil", "highlighter", "signature", "textformat",
        "list.number", "list.bullet.clipboard", "doc.append", "printer",
        "tag", "folder", "bookmark", "tray", "archivebox", "rectangle.stack", "externaldrive", "square.grid.2x2",
        "square.stack", "tray.and.arrow.down", "tray.and.arrow.up", "arrow.down.doc", "arrow.up.doc", "trash",
        "line.3.horizontal.decrease.circle", "arrow.up.arrow.down", "square.and.arrow.up",
        "checklist", "star", "flag", "calendar", "clock", "bell", "alarm", "timer", "hourglass",
        "checkmark.circle", "exclamationmark.triangle", "target", "calendar.badge.clock",
        "calendar.badge.checkmark", "arrow.clockwise", "repeat", "pin",
        "briefcase", "building.2", "person.2", "person.3", "person.crop.rectangle", "building.columns",
        "building", "wrench.and.screwdriver", "hammer", "gearshape", "puzzlepiece", "hand.raised",
        "rectangle.connected.to.line.below", "megaphone", "lifepreserver", "checkmark.seal", "medal",
        "book", "character.bubble", "lightbulb", "books.vertical", "graduationcap", "pencil", "text.book.closed",
        "newspaper", "binoculars", "magnifyingglass", "info.circle", "questionmark.circle", "character",
        "textformat.abc", "brain", "atom", "testtube.2",
        "envelope", "bubble.left", "person.crop.circle", "phone", "at", "bubble.left.and.bubble.right",
        "envelope.open", "envelope.badge", "paperplane", "message", "person.text.rectangle", "person.badge.plus",
        "phone.arrow.up.right", "video", "mic", "questionmark.bubble", "bell.badge",
        "globe", "link", "network", "wifi", "antenna.radiowaves.left.and.right", "cloud",
        "externaldrive.connected.to.line.below", "arrow.down.to.line", "arrow.up.to.line",
        "arrow.triangle.2.circlepath", "cursorarrow.click", "personalhotspot", "cable.connector", "wifi.router",
        "network.slash", "rectangle.and.text.magnifyingglass", "point.3.connected.trianglepath.dotted",
        "chevron.left.slash.chevron.right", "terminal", "curlybraces", "arrow.triangle.branch", "ant", "cylinder",
        "server.rack", "laptopcomputer", "desktopcomputer", "keyboard", "cpu", "memorychip", "text.cursor",
        "command", "function", "slider.horizontal.3", "app",
        "tablecells", "chart.bar", "chart.pie", "chart.line.uptrend.xyaxis", "gauge.with.dots.needle.50percent",
        "chart.dots.scatter", "chart.bar.doc.horizontal", "list.bullet.rectangle", "list.bullet.indent",
        "percent", "sum", "number", "plus.forwardslash.minus", "equal", "ruler", "scalemass",
        "doc.text.magnifyingglass",
        "lock", "key", "lock.shield", "lock.open", "person.badge.key", "shield", "checkmark.shield",
        "exclamationmark.shield", "eye", "eye.slash", "hand.raised.slash", "person.crop.circle.badge.checkmark",
        "person.crop.circle.badge.exclamationmark", "qrcode", "rectangle.badge.person.crop", "lock.rectangle",
        "rectangle.on.rectangle.slash",
        "cart", "receipt", "creditcard", "shippingbox", "bag", "basket", "gift", "wallet.bifold", "banknote",
        "dollarsign.circle", "yensign.circle", "eurosign.circle", "barcode", "creditcard.and.123",
        "yensign.arrow.circlepath", "list.clipboard", "arrow.left.arrow.right",
        "mappin", "ticket", "map", "location", "airplane", "car", "bus", "train.side.front.car", "fuelpump",
        "parkingsign.circle", "bed.double", "house", "door.left.hand.open", "fork.knife", "cup.and.saucer",
        "suitcase.rolling", "signpost.right",
        "photo", "camera", "film", "play.rectangle", "music.note", "waveform", "speaker.wave.2", "headphones",
        "pianokeys", "guitars", "paintbrush", "paintpalette", "pencil.and.outline", "crop", "scissors",
        "viewfinder", "photo.on.rectangle",
        "heart", "cross.case", "stethoscope", "pills", "leaf", "pawprint", "flame", "drop", "sun.max", "moon",
        "cloud.rain", "snowflake", "bolt", "bicycle", "figure.walk", "dumbbell", "sportscourt"
    ]

    static let availableSymbols = iconSymbols.filter { symbol in
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
    }
    private static let availableSymbolSet = Set(availableSymbols)

    static func iconTitleKey(for symbol: String) -> String {
        "category.icon.\(symbol)"
    }

    // ビルトインカテゴリ（削除不可）
    private static let builtInNoneID = BuiltInCategory.none
    private static let builtInURLID = BuiltInCategory.url
    private static var builtInNone: UserCategory {
        UserCategory(
            id: builtInNoneID,
            name: "None",
            iconSystemName: "tag.slash",
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
    private static var builtIns: [UserCategory] {
        [
            builtInNone, builtInURL,
            UserCategory(id: BuiltInCategory.ocr, name: "OCR", iconSystemName: "text.viewfinder"),
            UserCategory(id: BuiltInCategory.ai, name: "AI", iconSystemName: "sparkles")
        ]
    }

    func noneCategory() -> UserCategory { Self.builtInNone }
    func noneCategoryId() -> UUID { Self.builtInNoneID }
    func urlCategory() -> UserCategory { Self.builtInURL }
    func urlCategoryId() -> UUID { Self.builtInURLID }

    enum BuiltInKind { case none, url, ocr, ai }
    func builtInKind(for id: UUID) -> BuiltInKind? {
        if id == Self.builtInNoneID { return BuiltInKind.none }
        if id == Self.builtInURLID { return .url }
        if id == BuiltInCategory.ocr { return .ocr }
        if id == BuiltInCategory.ai { return .ai }
        return nil
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        filterOrder = defaults.stringArray(forKey: Self.filterOrderKey)?.compactMap(UUID.init(uuidString:)) ?? []
        load()
    }

    /// すべて（ビルトイン＋ユーザ定義）
    func all() -> [UserCategory] { Self.builtIns + categories }

    func assignable() -> [UserCategory] { all().filter { $0.id != BuiltInCategory.none } }

    func orderedForFiltering() -> [UserCategory] {
        let categories = assignable() + [Self.builtInNone]
        var remaining = Dictionary(categories.map { ($0.id, $0) }) { first, _ in first }
        let ordered = filterOrder.compactMap { remaining.removeValue(forKey: $0) }
        return ordered + categories.compactMap { remaining.removeValue(forKey: $0.id) }
    }

    func moveFilter(_ id: UUID, to target: UUID, among visibleIDs: [UUID]) {
        let visible = Set(visibleIDs)
        let order = orderedForFiltering().map(\.id)
        var visibleOrder = order.filter { visible.contains($0) }
        guard let from = visibleOrder.firstIndex(of: id), let to = visibleOrder.firstIndex(of: target),
              from != to else { return }

        let moved = visibleOrder.remove(at: from)
        visibleOrder.insert(moved, at: to)
        var reordered = visibleOrder.makeIterator()
        let updated = order.map { visible.contains($0) ? (reordered.next() ?? $0) : $0 }
        saveFilterOrder(updated)
    }

    func moveFiltersToEnd(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let order = orderedForFiltering().map(\.id)
        let updated = order.filter { !ids.contains($0) } + order.filter { ids.contains($0) }
        if updated != order { saveFilterOrder(updated) }
    }

    func categories(for item: ClipItem) -> [UserCategory] {
        categories(forIDs: item.categoryIDs)
    }

    func categories(forIDs ids: Set<UUID>) -> [UserCategory] {
        return assignable().filter { ids.contains($0.id) }
    }

    func isFilterEnabled(_ category: UserCategory) -> Bool {
        switch builtInKind(for: category.id) {
        case .some(.none): return AppSettings.shared.filterCategoryNone
        case .url: return AppSettings.shared.filterCategoryURL
        case .ocr: return AppSettings.shared.filterCategoryOCR
        case .ai: return AppSettings.shared.filterCategoryAI
        case nil: return category.isFilterEnabled
        }
    }

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

    func iconName(for categories: [UserCategory]) -> String {
        if categories.count > 1 { return "square.stack" }
        return iconName(for: categories.first ?? noneCategory())
    }

    func add(name: String, iconSystemName: String, id: UUID = UUID()) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let symbol = Self.availableSymbolSet.contains(iconSystemName)
            ? iconSystemName : "tag"
        let new = UserCategory(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                               iconSystemName: symbol,
                               isFilterEnabled: true)
        categories.append(new)
    }

    func remove(id: UUID) {
        guard !isBuiltIn(id) else { return }
        categories.removeAll { $0.id == id }
        if filterOrder.contains(id) { saveFilterOrder(filterOrder.filter { $0 != id }) }
    }

    func rename(id: UUID, to name: String) {
        guard !isBuiltIn(id), let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
    }

    func changeIcon(id: UUID, to systemName: String) {
        guard !isBuiltIn(id), let index = categories.firstIndex(where: { $0.id == id }) else { return }
        if Self.availableSymbolSet.contains(systemName) {
            categories[index].iconSystemName = systemName
        }
    }

    func setFilterEnabled(id: UUID, _ enabled: Bool) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].isFilterEnabled = enabled
    }

    // MARK: - Persistence
    private func saveFilterOrder(_ order: [UUID]) {
        filterOrder = order
        defaults.set(order.map(\.uuidString), forKey: Self.filterOrderKey)
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(categories)
            defaults.set(data, forKey: storageKey)
        } catch {
            Logger.shared.error("Failed to save categories: \(error)")
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
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
        if availableSymbolSet.contains(symbol) {
            return symbol
        }
        if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
            return symbol
        }
        return "tag"
    }
}
