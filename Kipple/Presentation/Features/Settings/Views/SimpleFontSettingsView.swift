//
//  SimpleFontSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/01.
//

import SwiftUI
import AppKit

struct SimpleFontSettingsView: View {
    @ObservedObject var fontManager = FontManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Editor Font Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Font Settings
            VStack(alignment: .leading, spacing: 16) {
                // Font Family
                HStack {
                    Text("Font:")
                        .frame(width: 80, alignment: .trailing)
                    
                    SearchableFontPicker(selectedFont: fontNameBinding)
                }
                
                // Fallback Font
                HStack {
                    Text("Fallback:")
                        .frame(width: 80, alignment: .trailing)
                    
                    SearchableFontPicker(selectedFont: fallbackFontBinding, includeNone: true)
                }
                
                // Font Size
                HStack {
                    Text("Size:")
                        .frame(width: 80, alignment: .trailing)
                    
                    TextField("", value: fontSizeBinding, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    
                    Stepper("", value: fontSizeBinding, in: 10...24, step: 1)
                        .labelsHidden()
                }
            }
            
            Divider()
            
            // Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                ScrollView {
                    Text("The quick brown fox jumps over the lazy dog\n素早い茶色のキツネが怠け者の犬を飛び越える\n1234567890 !@#$%^&*()")
                        .font(previewFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Helper Properties
    
    private var fontNameBinding: Binding<String> {
        return $fontManager.editorSettings.primaryFontName
    }
    
    private var fallbackFontBinding: Binding<String> {
        return Binding(
            get: { fontManager.editorSettings.fallbackFontNames.first ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    fontManager.editorSettings.fallbackFontNames = []
                } else {
                    fontManager.editorSettings.fallbackFontNames = [newValue]
                }
            }
        )
    }
    
    private var fontSizeBinding: Binding<CGFloat> {
        return $fontManager.editorSettings.primaryFontSize
    }
    
    private var previewFont: Font {
        let fontName = fontNameBinding.wrappedValue
        let fontSize = fontSizeBinding.wrappedValue
        
        if fontName == "System" {
            return .system(size: fontSize, design: .monospaced)
        } else {
            return Font.custom(fontName, size: fontSize)
        }
    }
    
    // MARK: - Helper Methods
    
    private func availableMonospacedFonts() -> [String] {
        return FontManager.availableMonospacedFonts()
    }
    
    private func availableFallbackFonts() -> [String] {
        // Filter out the currently selected primary font
        let primaryFont = fontManager.editorSettings.primaryFontName
        return FontManager.availableMonospacedFonts().filter { $0 != primaryFont }
    }
    
    private func fontDisplayName(for fontName: String) -> String {
        return FontNameMappings.displayName(for: fontName)
    }
}
