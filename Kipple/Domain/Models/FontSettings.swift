//
//  FontSettings.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import Foundation
import AppKit
import SwiftUI

struct FontSettings: Codable, Equatable {
    var primaryFontName: String
    var primaryFontSize: CGFloat
    var fallbackFontNames: [String]
    var lineHeightMultiple: CGFloat = 1.4
    
    // 統合フォントリスト（プライマリ + フォールバック）
    var fontList: [String] {
        get {
            var list = [primaryFontName]
            list.append(contentsOf: fallbackFontNames)
            return list
        }
        set {
            if !newValue.isEmpty {
                primaryFontName = newValue[0]
                fallbackFontNames = Array(newValue.dropFirst())
            }
        }
    }
    
    static let `default` = FontSettings(
        primaryFontName: "SFMono-Regular",
        primaryFontSize: 14,
        fallbackFontNames: ["Menlo-Regular"],
        lineHeightMultiple: 1.4
    )
    
    // 利用可能なフォントを取得（存在チェック）
    func getAvailableFont() -> NSFont {
        // プライマリフォントを試す
        if let font = NSFont(name: primaryFontName, size: primaryFontSize) {
            return font
        }
        
        // フォールバックフォントを順番に試す
        for fontName in fallbackFontNames {
            if let font = NSFont(name: fontName, size: primaryFontSize) {
                return font
            }
        }
        
        // すべて失敗した場合はシステムフォントを返す
        return NSFont.monospacedSystemFont(ofSize: primaryFontSize, weight: .regular)
    }
    
    // フォント名リストから実際のフォントを構築
    func buildFont() -> NSFont {
        return getAvailableFont()
    }
    
    // 設定が有効かチェック
    var isValid: Bool {
        // 少なくとも一つのフォントが利用可能であること
        if NSFont(name: primaryFontName, size: primaryFontSize) != nil {
            return true
        }
        
        for fontName in fallbackFontNames where NSFont(name: fontName, size: primaryFontSize) != nil {
            return true
        }
        
        return false
    }
}

// MARK: - Font Manager
class FontManager: ObservableObject {
    static let shared = FontManager()
    
    @Published var editorSettings: FontSettings {
        didSet {
            saveEditorFontSettings()
            NotificationCenter.default.post(name: .editorFontSettingsChanged, object: nil)
        }
    }
    
    @Published var historySettings: FontSettings {
        didSet {
            saveHistoryFontSettings()
            NotificationCenter.default.post(name: .historyFontSettingsChanged, object: nil)
        }
    }
    
    @Published var editorLayoutSettings: EditorLayoutSettings {
        didSet {
            saveEditorLayoutSettings()
            NotificationCenter.default.post(name: .editorLayoutSettingsChanged, object: nil)
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let editorFontSettingsKey = "editorFontSettings"
    private let historyFontSettingsKey = "historyFontSettings"
    
    private init() {
        self.editorSettings = Self.loadEditorFontSettings()
        self.historySettings = Self.loadHistoryFontSettings()
        self.editorLayoutSettings = Self.loadEditorLayoutSettings()
    }
    
    static func loadEditorFontSettings() -> FontSettings {
        guard let data = UserDefaults.standard.data(forKey: "editorFontSettings"),
              let settings = try? JSONDecoder().decode(FontSettings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    static func loadHistoryFontSettings() -> FontSettings {
        guard let data = UserDefaults.standard.data(forKey: "historyFontSettings"),
              let settings = try? JSONDecoder().decode(FontSettings.self, from: data) else {
            // 既存の@AppStorage値から移行
            let historyFontName = UserDefaults.standard.string(forKey: "historyFontName") ?? "System"
            let historyFallbackFontName = UserDefaults.standard.string(forKey: "historyFallbackFontName") ?? ""
            let historyFontSize = UserDefaults.standard.double(forKey: "historyFontSize")
            
            let fontName = historyFontName == "System" ? "SFMono-Regular" : historyFontName
            let fallbacks = historyFallbackFontName.isEmpty ? ["Menlo-Regular"] : [historyFallbackFontName]
            let size = historyFontSize > 0 ? CGFloat(historyFontSize) : 13
            
            return FontSettings(
                primaryFontName: fontName,
                primaryFontSize: size,
                fallbackFontNames: fallbacks,
                lineHeightMultiple: 1.4
            )
        }
        return settings
    }
    
    private func saveEditorFontSettings() {
        guard let data = try? JSONEncoder().encode(editorSettings) else { return }
        userDefaults.set(data, forKey: editorFontSettingsKey)
    }
    
    private func saveHistoryFontSettings() {
        guard let data = try? JSONEncoder().encode(historySettings) else { return }
        userDefaults.set(data, forKey: historyFontSettingsKey)
    }
    
    private func saveEditorLayoutSettings() {
        guard let data = try? JSONEncoder().encode(editorLayoutSettings) else { return }
        userDefaults.set(data, forKey: "editorLayoutSettings")
    }
    
    // エディター用フォントを取得
    var editorFont: NSFont {
        editorSettings.getAvailableFont()
    }
    
    // 履歴用フォントを取得
    var historyFont: NSFont {
        historySettings.getAvailableFont()
    }
    
    // すべてのフォント（プライマリ＋フォールバック）の最大行高を計算
    var maxLineHeight: CGFloat {
        var maxHeight: CGFloat = 0
        
        // 各フォントで最大行高を計算（フォントメトリクスのみを使用）
        for fontName in editorSettings.fontList {
            if let font = NSFont(name: fontName, size: editorSettings.primaryFontSize) {
                // フォントメトリクスから基本的な行高を取得
                let fontHeight = font.ascender - font.descender + font.leading
                maxHeight = max(maxHeight, fontHeight)
            }
        }
        
        // 日本語フォントの代表的なフォントも考慮
        let japaneseTestFonts = ["HiraginoSans-W3", "YuGothic-Medium", "NotoSansCJK-Regular"]
        for fontName in japaneseTestFonts {
            if let font = NSFont(name: fontName, size: editorSettings.primaryFontSize) {
                let fontHeight = font.ascender - font.descender + font.leading
                maxHeight = max(maxHeight, fontHeight)
            }
        }
        
        // フォントサイズに基づく最小値（より大きく設定）
        let minimumHeight = editorSettings.primaryFontSize * 1.4
        
        // 基本的なフォント高さを使用（lineHeightMultipleは適用しない）
        let baseHeight = max(maxHeight, minimumHeight)
        return baseHeight
    }
    
    // システムで利用可能なすべてのフォントを取得（メソッド名は互換性のため維持）
    static func availableMonospacedFonts() -> [String] {
        let fontManager = NSFontManager.shared
        let fontFamilies = fontManager.availableFontFamilies
        
        var fonts: [String] = []
        
        for family in fontFamilies {
            if shouldExcludeFontFamily(family) {
                continue
            }
            
            if let members = fontManager.availableMembers(ofFontFamily: family),
               let fontName = selectBestFontFromFamily(members) {
                fonts.append(fontName)
            }
        }
        
        // アルファベット順にソート
        return fonts.sorted { a, b in
            // 日本語フォントを優先的に表示
            let aIsJapanese = isJapaneseFont(a)
            let bIsJapanese = isJapaneseFont(b)
            
            if aIsJapanese && !bIsJapanese {
                return true
            } else if !aIsJapanese && bIsJapanese {
                return false
            }
            
            // 等幅フォントを次に優先
            let aIsMono = isMonospaceFont(a)
            let bIsMono = isMonospaceFont(b)
            
            if aIsMono && !bIsMono {
                return true
            } else if !aIsMono && bIsMono {
                return false
            }
            
            // それ以外はアルファベット順
            return a < b
        }
    }
    
    // フォントファミリーを除外すべきかチェック
    private static func shouldExcludeFontFamily(_ family: String) -> Bool {
        let familyLower = family.lowercased()
        return familyLower.contains("emoji") ||
               familyLower.contains("symbol") ||
               familyLower.contains("webdings") ||
               familyLower.contains("wingdings") ||
               familyLower.contains("dingbats") ||
               familyLower.contains("ornaments") ||
               familyLower.contains("pictograph") ||
               familyLower.contains("braille")
    }
    
    // ファミリーから最適なフォントを選択
    private static func selectBestFontFromFamily(_ members: [[Any]]) -> String? {
        // Regularまたは標準的なウェイトを探す
        for member in members {
            if let name = member[0] as? String,
               let weight = member[2] as? Int {
                
                let lowerName = name.lowercased()
                
                // 特殊なバリアントは除外（イタリック体など）
                if lowerName.contains("italic") ||
                   lowerName.contains("oblique") {
                    continue
                }
                
                // Regular (weight 5) または Medium (weight 6) を優先
                if weight == 5 || weight == 6 ||
                   lowerName.contains("-regular") ||
                   lowerName.contains("-medium") ||
                   lowerName.contains("-w3") ||  // 日本語フォントの標準ウェイト
                   lowerName.contains("-w4") {
                    return name
                }
            }
        }
        
        // 適切なウェイトが見つからない場合は最初の非イタリックメンバーを使用
        for member in members {
            if let name = member[0] as? String {
                let lowerName = name.lowercased()
                if !lowerName.contains("italic") && !lowerName.contains("oblique") {
                    return name
                }
            }
        }
        
        // それでも見つからない場合は最初のメンバーを使用
        if let firstMember = members.first,
           let fontName = firstMember[0] as? String {
            return fontName
        }
        
        return nil
    }
    
    // 日本語フォントかどうかを判定
    private static func isJapaneseFont(_ fontName: String) -> Bool {
        let name = fontName.lowercased()
        return fontName.contains("Hiragino") ||
               fontName.contains("Yu") ||
               fontName.contains("Osaka") ||
               fontName.contains("Noto") && (name.contains("jp") || name.contains("cjk")) ||
               fontName.contains("Source Han") ||
               fontName.contains("ヒラギノ") ||
               fontName.contains("游") ||
               name.contains("gothic") ||
               name.contains("mincho")
    }
    
    // 等幅フォントかどうかを簡易判定（名前ベース）
    private static func isMonospaceFont(_ fontName: String) -> Bool {
        let name = fontName.lowercased()
        return name.contains("mono") ||
               name.contains("code") ||
               name.contains("courier") ||
               name.contains("menlo") ||
               name.contains("monaco") ||
               name.contains("consolas") ||
               name.contains("等幅")
    }
}

// MARK: - Editor Layout Settings (Developer Only)
struct EditorLayoutSettings: Codable {
    var lineHeightMultiplier: CGFloat = 1.5
    var verticalPadding: CGFloat = 5.0
    var lineNumberVerticalOffset: CGFloat = -7.0
    var minimumLineHeightMultiplier: CGFloat = 1.8
    var textBaselineOffset: CGFloat = -1.0  // テキストのベースライン調整
    
    static let `default` = EditorLayoutSettings()
}

extension FontManager {
    static func loadEditorLayoutSettings() -> EditorLayoutSettings {
        guard let data = UserDefaults.standard.data(forKey: "editorLayoutSettings"),
              let settings = try? JSONDecoder().decode(EditorLayoutSettings.self, from: data) else {
            return .default
        }
        return settings
    }
}

// MARK: - Notification
extension Notification.Name {
    static let editorFontSettingsChanged = Notification.Name("editorFontSettingsChanged")
    static let historyFontSettingsChanged = Notification.Name("historyFontSettingsChanged")
    static let editorLayoutSettingsChanged = Notification.Name("editorLayoutSettingsChanged")
}
