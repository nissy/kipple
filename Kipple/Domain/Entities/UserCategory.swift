//
//  UserCategory.swift
//  Kipple
//
//  Userが定義する単色アイコン前提のテキスト関連カテゴリ。
//

import Foundation

struct UserCategory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// SF Symbols の systemName を保存（単色前提）
    var iconSystemName: String
    /// フィルタ（上部チップ）に表示するか
    var isFilterEnabled: Bool

    init(id: UUID = UUID(), name: String, iconSystemName: String, isFilterEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.iconSystemName = iconSystemName
        self.isFilterEnabled = isFilterEnabled
    }

    // Codable: 過去データとの互換性のため isFilterEnabled をデフォルト true
    enum CodingKeys: String, CodingKey {
        case id, name, iconSystemName, isFilterEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iconSystemName = try container.decode(String.self, forKey: .iconSystemName)
        isFilterEnabled = try container.decodeIfPresent(Bool.self, forKey: .isFilterEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(iconSystemName, forKey: .iconSystemName)
        try container.encode(isFilterEnabled, forKey: .isFilterEnabled)
    }
}
