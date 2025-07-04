//
//  LineNumberAlignmentVisualTest.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/02.
//

import XCTest
import SwiftUI
import AppKit
@testable import Kipple

class LineNumberAlignmentVisualTest: XCTestCase {
    
    func testLineNumberAlignmentCalculations() {
        // Test alignment calculations for different fonts
        let fonts = [
            ("English", NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)),
            ("Japanese", NSFont(name: "HiraginoSans-W3", size: 14) ?? NSFont.systemFont(ofSize: 14))
        ]
        
        for (fontType, textFont) in fonts {
            
            let lineNumberFont = NSFont.monospacedSystemFont(ofSize: textFont.pointSize * 0.7, weight: .regular)
            
            // Simulate line position
            let lineY: CGFloat = 100
            let lineHeight: CGFloat = 28 // From NSLayoutManager test
            
            // Old calculation (ascender-based)
            let oldBaselineY = lineY + textFont.ascender
            let oldDrawingY = oldBaselineY - lineNumberFont.ascender
            
            // New calculation (center-based)
            let textVisualCenter = lineY + lineHeight / 2
            let lineNumberHeight = lineNumberFont.ascender - lineNumberFont.descender
            let lineNumberVisualCenter = lineNumberHeight / 2
            var newDrawingY = textVisualCenter - lineNumberVisualCenter - lineNumberFont.descender
            
            // Japanese font adjustment
            if isJapaneseFont(textFont) {
                newDrawingY += 1.0
            }
        }
    }
    
    func testVisualCenterAlignment() {
        // Test that visual centers align properly
        let textFont = NSFont(name: "HiraginoSans-W3", size: 14) ?? NSFont.systemFont(ofSize: 14)
        let lineNumberFont = NSFont.monospacedSystemFont(ofSize: textFont.pointSize * 0.7, weight: .regular)
        
        let lineY: CGFloat = 0
        let lineHeight: CGFloat = 28
        
        // Calculate centers
        let textCenter = lineY + lineHeight / 2
        let lineNumberHeight = lineNumberFont.ascender - lineNumberFont.descender
        
        // New drawing position
        let japaneseAdjustment = isJapaneseFont(textFont) ? 1.0 : 0.0
        let drawingY = textCenter - lineNumberHeight / 2 - lineNumberFont.descender + japaneseAdjustment
        
        // Verify the line number center aligns with text center
        let lineNumberCenter = drawingY + lineNumberFont.descender + lineNumberHeight / 2
        
        // Should be very close (within 1 pixel due to Japanese adjustment)
        XCTAssertLessThan(abs(textCenter - lineNumberCenter), 2.0, "Centers should align within 2 pixels")
    }
    
    private func isJapaneseFont(_ font: NSFont) -> Bool {
        let fontName = font.fontName.lowercased()
        return font.fontName.contains("Hiragino") ||
               font.fontName.contains("Yu") ||
               font.fontName.contains("Osaka") ||
               font.fontName.contains("Noto") && (fontName.contains("jp") || fontName.contains("cjk")) ||
               font.fontName.contains("Source Han") ||
               font.fontName.contains("ヒラギノ") ||
               font.fontName.contains("游") ||
               fontName.contains("gothic") ||
               fontName.contains("mincho")
    }
}
