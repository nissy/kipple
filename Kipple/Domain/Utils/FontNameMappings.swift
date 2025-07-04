//
//  FontNameMappings.swift
//  Kipple
//
//  Created by Kipple on 2025/07/01.
//

import Foundation

struct FontNameMappings {
    static func displayName(for fontName: String) -> String {
        // Check for special variants first
        if let specialName = checkSpecialVariants(fontName) {
            return specialName
        }
        
        // Check font mapping dictionaries
        if let mappedName = checkFontMappings(fontName) {
            return mappedName
        }
        
        // Default processing
        return processDefaultName(fontName)
    }
    
    private static func checkSpecialVariants(_ fontName: String) -> String? {
        let specialMappings: [(prefix: String, variants: [(suffix: String, name: String)])] = [
            ("HiraginoSans-", [
                ("W3", "ヒラギノ角ゴシック W3"),
                ("W6", "ヒラギノ角ゴシック W6")
            ]),
            ("HiraKakuPro", [
                ("W3", "ヒラギノ角ゴ Pro W3"),
                ("W6", "ヒラギノ角ゴ Pro W6")
            ]),
            ("HiraMinPro", [
                ("W3", "ヒラギノ明朝 Pro W3"),
                ("W6", "ヒラギノ明朝 Pro W6")
            ]),
            ("YuGothic-", [
                ("Bold", "游ゴシック Bold"),
                ("Medium", "游ゴシック Medium")
            ]),
            ("YuMincho-", [
                ("Demibold", "游明朝 Demibold")
            ]),
            ("NotoSansCJK", [
                ("jp", "Noto Sans CJK JP"),
                ("sc", "Noto Sans CJK SC"),
                ("tc", "Noto Sans CJK TC"),
                ("kr", "Noto Sans CJK KR")
            ]),
            ("Osaka", [
                ("Mono", "Osaka 等幅")
            ])
        ]
        
        for mapping in specialMappings where fontName.hasPrefix(mapping.prefix) {
            for variant in mapping.variants where fontName.contains(variant.suffix) {
                return variant.name
            }
        }
        
        return nil
    }
    
    private static func checkFontMappings(_ fontName: String) -> String? {
        let simpleMappings: [String: String] = [
            // Japanese fonts
            "HiraginoSans": "ヒラギノ角ゴシック",
            "HiraKakuPro": "ヒラギノ角ゴ Pro",
            "HiraKakuProN": "ヒラギノ角ゴ Pro",
            "HiraMaruPro": "ヒラギノ丸ゴ Pro",
            "HiraMaruProN": "ヒラギノ丸ゴ Pro",
            "HiraMinPro": "ヒラギノ明朝 Pro",
            "HiraMinProN": "ヒラギノ明朝 Pro",
            "YuGothic": "游ゴシック",
            "YuMincho": "游明朝",
            "YuKyokasho": "游教科書体",
            "TsukushiAMaruGothic": "筑紫A丸ゴシック",
            "TsukushiBMaruGothic": "筑紫B丸ゴシック",
            "Klee": "クレー",
            "Osaka": "Osaka",
            
            // CJK fonts
            "PingFang": "蘋方",
            "NotoSansCJK": "Noto Sans CJK",
            "NotoSerifCJK": "Noto Serif CJK",
            "SourceHanSans": "Source Han Sans",
            "SourceHanSerif": "Source Han Serif",
            "SourceHanCodeJP": "Source Han Code JP",
            
            // Monospace fonts
            "SFMono": "SF Mono",
            "Menlo": "Menlo",
            "Monaco": "Monaco",
            "Courier": "Courier",
            "Courier New": "Courier New",
            "Andale Mono": "Andale Mono",
            "Consolas": "Consolas",
            "JetBrainsMono": "JetBrains Mono",
            "FiraCode": "Fira Code",
            "SourceCodePro": "Source Code Pro",
            
            // Regular fonts
            "Helvetica": "Helvetica",
            "Arial": "Arial",
            "Times": "Times",
            "Georgia": "Georgia",
            "Verdana": "Verdana"
        ]
        
        for (key, value) in simpleMappings where fontName.hasPrefix(key) {
            return value
        }
        
        return nil
    }
    
    private static func processDefaultName(_ fontName: String) -> String {
        if fontName.contains("-Regular") {
            return fontName.replacingOccurrences(of: "-Regular", with: "")
        } else if fontName.contains("Regular") && fontName.hasSuffix("Regular") {
            return String(fontName.dropLast(7)).trimmingCharacters(in: .whitespaces)
        }
        
        return fontName
    }
}
