//
//  RangedNumberField.swift
//  Kipple
//
//  Created by Kipple on 2025/06/29.
//

import SwiftUI

struct RangedNumberField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String?
    
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool
    @State private var showingOutOfRangeWarning = false
    
    init(title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String? = nil) {
        self.title = title
        self._value = value
        self.range = range
        self.suffix = suffix
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                
                TextField("", text: $textValue)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onAppear {
                        textValue = String(value)
                    }
                    .onChange(of: textValue) { newValue in
                        validateAndUpdate(newValue)
                    }
                    .onChange(of: isFocused) { focused in
                        if !focused {
                            // フォーカスを失った時のみ制約チェック
                            enforceRangeConstraints()
                        }
                    }
                    .onChange(of: value) { newValue in
                        if !isFocused {
                            textValue = String(newValue)
                            showingOutOfRangeWarning = false
                        }
                    }
                    // 範囲が変更された時の処理を追加
                    .onChange(of: range) { _ in
                        let clamped = min(max(value, range.lowerBound), range.upperBound)
                        if value != clamped {
                            value = clamped
                            textValue = String(clamped)
                        }
                    }
                
                if let suffix = suffix {
                    Text(suffix)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("(\(range.lowerBound)-\(range.upperBound))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if showingOutOfRangeWarning {
                Text("Value will be adjusted to range \(range.lowerBound)-\(range.upperBound) when you finish editing")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    private func validateAndUpdate(_ text: String) {
        // 空の場合は警告を隠す
        if text.isEmpty {
            showingOutOfRangeWarning = false
            return
        }
        
        // 数値以外の文字を除去
        let filtered = text.filter { $0.isNumber }
        if filtered != text {
            textValue = filtered
            return
        }
        
        // 数値に変換して一時的に値を設定（範囲制限は行わない）
        if let number = Int(filtered) {
            value = number
            
            // 範囲外の場合は警告を表示
            if number < range.lowerBound || number > range.upperBound {
                showingOutOfRangeWarning = true
            } else {
                showingOutOfRangeWarning = false
            }
        }
    }
    
    private func enforceRangeConstraints() {
        // フォーカスを失った時に範囲制約を適用
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        if value != clamped {
            value = clamped
            textValue = String(clamped)
        }
        showingOutOfRangeWarning = false
    }
}
