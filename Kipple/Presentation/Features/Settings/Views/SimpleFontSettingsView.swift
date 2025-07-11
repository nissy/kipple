//
//  SimpleFontSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/01.
//

import SwiftUI

struct SimpleFontSettingsView: View {
    @ObservedObject var fontManager = FontManager.shared
    
    var body: some View {
        SettingsGroup("Editor Font") {
            SettingsRow(label: "Font") {
                SearchableFontPicker(selectedFont: fontNameBinding)
                    .frame(width: 200)
            }
            
            SettingsRow(label: "Fallback font") {
                SearchableFontPicker(selectedFont: fallbackFontBinding, includeNone: true)
                    .frame(width: 200)
            }
            
            SettingsRow(label: "Font size") {
                HStack {
                    TextField("", value: fontSizeBinding, formatter: makeFontSizeFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    
                    Stepper("", value: fontSizeBinding, in: 10...24, step: 1)
                        .labelsHidden()
                    
                    Text("pt")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                ScrollView {
                    Text("The quick brown fox jumps over the lazy dog\n素早い茶色のキツネが怠け者の犬を飛び越える\n1234567890 !@#$%^&*()\n😀🎉🚀 ∑∏∫√∞ ™®©")
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
        }
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
        // FontManagerから実際のフォント（フォールバックチェーン含む）を取得
        return Font(fontManager.editorFont)
    }
    
    private func makeFontSizeFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 10
        formatter.maximum = 24
        formatter.generatesDecimalNumbers = false
        formatter.allowsFloats = false
        return formatter
    }
}
