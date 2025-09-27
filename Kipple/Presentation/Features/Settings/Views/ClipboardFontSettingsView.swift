//
//  ClipboardFontSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/01.
//

import SwiftUI

struct ClipboardFontSettingsView: View {
    @ObservedObject var fontManager = FontManager.shared
    
    var body: some View {
        SettingsGroup("History Font") {
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
        }
    }
    
    // MARK: - Helper Properties
    
    private var fontNameBinding: Binding<String> {
        return $fontManager.historySettings.primaryFontName
    }
    
    private var fallbackFontBinding: Binding<String> {
        return Binding(
            get: { fontManager.historySettings.fallbackFontNames.first ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    fontManager.historySettings.fallbackFontNames = []
                } else {
                    fontManager.historySettings.fallbackFontNames = [newValue]
                }
            }
        )
    }
    
    private var fontSizeBinding: Binding<CGFloat> {
        return $fontManager.historySettings.primaryFontSize
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
