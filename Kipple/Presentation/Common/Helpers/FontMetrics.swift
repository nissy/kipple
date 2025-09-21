//
//  FontMetrics.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import AppKit

@MainActor
struct FontMetrics {
    private static let lineHeightCache = NSCache<NSString, NSNumber>()
    
    static func lineHeight(for fontName: String, fontSize: CGFloat) -> CGFloat {
        let cacheKey = "\(fontName)#\(fontSize)" as NSString
        if let cached = lineHeightCache.object(forKey: cacheKey) {
            return CGFloat(truncating: cached)
        }
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        
        // NSTextViewを使用して実際の行高を計算
        let textView = NSTextView()
        textView.font = font
        textView.string = "Sample\nText"
        
        // レイアウトマネージャーから正確な行高を取得
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            
            // 強制的にレイアウトを実行
            layoutManager.ensureLayout(for: textContainer)
            
            // 最初の行の矩形を取得
            let firstLineRect = layoutManager.lineFragmentRect(
                forGlyphAt: 0,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            
            // 2行目の矩形を取得
            let secondLineRect = layoutManager.lineFragmentRect(
                forGlyphAt: 7,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            
            // 実際の行間隔を計算
            let lineSpacing = secondLineRect.minY - firstLineRect.minY
            
            // 行間隔が0の場合は、デフォルトの計算を使用
            if lineSpacing > 0 {
                lineHeightCache.setObject(NSNumber(value: Double(lineSpacing)), forKey: cacheKey)
                return lineSpacing
            }
        }
        
        // フォールバック: フォントメトリクスから計算
        // NSTextViewのデフォルトの行間隔係数は約1.2
        let baseHeight = font.ascender - font.descender + font.leading
        let calculated = baseHeight * 1.2
        lineHeightCache.setObject(NSNumber(value: Double(calculated)), forKey: cacheKey)
        return calculated
    }
    
    static func baselineOffset(for fontName: String, fontSize: CGFloat) -> CGFloat {
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        return font.ascender
    }
}
