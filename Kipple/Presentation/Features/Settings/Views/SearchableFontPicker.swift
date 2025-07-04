//
//  SearchableFontPicker.swift
//  Kipple
//
//  Created by Kipple on 2025/07/01.
//

import SwiftUI
import AppKit

struct SearchableFontPicker: View {
    @Binding var selectedFont: String
    @State private var searchText = ""
    @State private var isShowingPopover = false
    @Environment(\.colorScheme) var colorScheme
    let includeNone: Bool
    
    init(selectedFont: Binding<String>, includeNone: Bool = false) {
        self._selectedFont = selectedFont
        self.includeNone = includeNone
    }
    
    private let allFonts = FontManager.availableMonospacedFonts()
    
    var body: some View {
        Button(action: { isShowingPopover.toggle() }) {
            HStack {
                Text(fontDisplayName(for: selectedFont))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .popover(
            isPresented: $isShowingPopover,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing  // 常に右側に表示
        ) {
            FontSelectionView(
                selectedFont: $selectedFont,
                searchText: $searchText,
                allFonts: allFonts,
                includeNone: includeNone
            ) { font in
                    selectedFont = font
                    isShowingPopover = false
                    // 最近使用したフォントに追加
                    if !font.isEmpty {
                        UserDefaults.standard.addRecentlyUsedFont(font)
                    }
            }
        }
    }
    
    private func fontDisplayName(for fontName: String) -> String {
        // SimpleFontSettingsViewと同じ実装
        if fontName.isEmpty {
            return "None"
        } else if fontName == "System" {
            return "System"
        } else if fontName.hasPrefix("SFMono-") {
            return "SF Mono"
        } else if fontName.hasPrefix("Menlo-") {
            return "Menlo"
        } else if fontName.hasPrefix("HiraginoSans-") {
            return "ヒラギノ角ゴシック"
        } else if fontName.hasPrefix("YuGothic-") {
            return "游ゴシック"
        }
        // 他のフォント名処理...
        return fontName.replacingOccurrences(of: "-Regular", with: "")
    }
}

struct FontSelectionView: View {
    @Binding var selectedFont: String
    @Binding var searchText: String
    let allFonts: [String]
    let includeNone: Bool
    let onSelect: (String) -> Void
    
    private var fontCategories: [(name: String, fonts: [String])] {
        var allFontsWithNone = allFonts
        if includeNone {
            allFontsWithNone.insert("", at: 0)
        }
        
        let filtered = searchText.isEmpty ? allFontsWithNone : allFontsWithNone.filter { font in
            if font.isEmpty {
                return "None".localizedCaseInsensitiveContains(searchText)
            }
            return fontDisplayName(for: font).localizedCaseInsensitiveContains(searchText)
        }
        
        if !searchText.isEmpty {
            return [("検索結果", filtered)]
        }
        
        // カテゴリー分け
        var recentlyUsed: [String] = []
        var japanese: [String] = []
        var monospaced: [String] = []
        var others: [String] = []
        
        // 最近使用したフォント（UserDefaultsから取得）
        if let recentFonts = UserDefaults.standard.array(forKey: "recentlyUsedFonts") as? [String] {
            recentlyUsed = Array(recentFonts.filter { filtered.contains($0) }.prefix(5))
        }
        
        for font in filtered {
            if isJapaneseFont(font) {
                japanese.append(font)
            } else if isMonospacedFont(font) {
                monospaced.append(font)
            } else {
                others.append(font)
            }
        }
        
        var categories: [(String, [String])] = []
        
        if !recentlyUsed.isEmpty {
            categories.append(("最近使用したフォント", recentlyUsed))
        }
        if !japanese.isEmpty {
            categories.append(("日本語フォント", japanese))
        }
        if !monospaced.isEmpty {
            categories.append(("等幅フォント", monospaced))
        }
        if !others.isEmpty {
            categories.append(("その他のフォント", others))
        }
        
        return categories
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 検索フィールド
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("フォントを検索...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // フォントリスト
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(fontCategories, id: \.name) { category in
                        // カテゴリーヘッダー
                        Text(category.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        
                        // フォントアイテム
                        ForEach(category.fonts, id: \.self) { font in
                            FontItemView(
                                font: font,
                                isSelected: font == selectedFont,
                                onSelect: onSelect
                            )
                        }
                    }
                }
            }
            .frame(width: 300, height: 400)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func fontDisplayName(for fontName: String) -> String {
        // 実装は上記と同じ
        if fontName == "System" { return "System" }
        if fontName.hasPrefix("SFMono-") { return "SF Mono" }
        if fontName.hasPrefix("Menlo-") { return "Menlo" }
        // ... 他のフォント名処理
        return fontName.replacingOccurrences(of: "-Regular", with: "")
    }
    
    private func isJapaneseFont(_ fontName: String) -> Bool {
        let name = fontName.lowercased()
        return fontName.contains("Hiragino") ||
               fontName.contains("Yu") ||
               fontName.contains("Osaka") ||
               fontName.contains("Noto") && (name.contains("jp") || name.contains("cjk"))
    }
    
    private func isMonospacedFont(_ fontName: String) -> Bool {
        let name = fontName.lowercased()
        return name.contains("mono") ||
               name.contains("code") ||
               name.contains("courier") ||
               name.contains("menlo") ||
               name.contains("monaco") ||
               name.contains("consolas")
    }
}

struct FontItemView: View {
    let font: String
    let isSelected: Bool
    let onSelect: (String) -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { onSelect(font) }) {
            HStack {
                // フォントプレビュー
                if font.isEmpty {
                    Text("None")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .leading)
                } else {
                    Text("Abc 123 あいう")
                        .font(Font.custom(font, size: 13))
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                }
                
                // フォント名
                Text(fontDisplayName(for: font))
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func fontDisplayName(for fontName: String) -> String {
        // 実装は上記と同じ
        if fontName.isEmpty { return "None" }
        if fontName.hasPrefix("SFMono-") { return "SF Mono" }
        if fontName.hasPrefix("Menlo-") { return "Menlo" }
        return fontName.replacingOccurrences(of: "-Regular", with: "")
    }
}

// MARK: - 最近使用したフォントの管理
extension UserDefaults {
    func addRecentlyUsedFont(_ fontName: String) {
        var recentFonts = (array(forKey: "recentlyUsedFonts") as? [String]) ?? []
        recentFonts.removeAll { $0 == fontName }
        recentFonts.insert(fontName, at: 0)
        if recentFonts.count > 10 {
            recentFonts = Array(recentFonts.prefix(10))
        }
        set(recentFonts, forKey: "recentlyUsedFonts")
    }
}
