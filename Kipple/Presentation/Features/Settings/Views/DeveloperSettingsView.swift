//
//  DeveloperSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

#if DEBUG
import SwiftUI

struct DeveloperSettingsView: View {
    @ObservedObject private var fontManager = FontManager.shared
    @State private var showDeveloperSettings = false
    @Environment(\.presentationMode) var presentationMode
    
    // Number formatters
    private var decimalFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("開発者設定")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Editor Layout Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("エディタレイアウト")
                            .font(.headline)
                        
                        // Line Height Multiplier
                        VStack(alignment: .leading, spacing: 8) {
                            Text("行の高さ倍率")
                                .font(.subheadline)
                            
                            TextField(
                                "1.5",
                                value: $fontManager.editorLayoutSettings.lineHeightMultiplier,
                                formatter: decimalFormatter
                            )
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Text("行の高さ計算に使用する倍率")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Minimum Line Height Multiplier
                        VStack(alignment: .leading, spacing: 8) {
                            Text("最小行高さ倍率")
                                .font(.subheadline)
                            
                            TextField(
                                "1.8",
                                value: $fontManager.editorLayoutSettings.minimumLineHeightMultiplier,
                                formatter: decimalFormatter
                            )
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Text("フォントサイズに対する最小行高さの倍率")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Vertical Padding
                        VStack(alignment: .leading, spacing: 8) {
                            Text("垂直パディング")
                                .font(.subheadline)
                            
                            TextField(
                                "5.0",
                                value: $fontManager.editorLayoutSettings.verticalPadding,
                                formatter: decimalFormatter
                            )
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Text("テキストコンテナの垂直方向の余白")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Line Number Vertical Offset
                        VStack(alignment: .leading, spacing: 8) {
                            Text("行番号の垂直オフセット")
                                .font(.subheadline)
                            
                            TextField(
                                "-7.0",
                                value: $fontManager.editorLayoutSettings.lineNumberVerticalOffset,
                                formatter: decimalFormatter
                            )
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Text("行番号の垂直位置調整（正の値 = 下へ、負の値 = 上へ）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Text Baseline Offset
                        VStack(alignment: .leading, spacing: 8) {
                            Text("テキストベースラインオフセット")
                                .font(.subheadline)
                            
                            TextField(
                                "-1.0",
                                value: $fontManager.editorLayoutSettings.textBaselineOffset,
                                formatter: decimalFormatter
                            )
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Text("カーソルに対するテキストの垂直位置調整（正の値 = 下へ、負の値 = 上へ）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Reset Button
                        Button(action: {
                            fontManager.editorLayoutSettings = .default
                        }) {
                            Text("デフォルトに戻す")
                                .font(.subheadline)
                        }
                        .buttonStyle(LinkButtonStyle())
                    }
                    .padding(.horizontal, 24)
                    
                    // Preview Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("プレビュー")
                            .font(.headline)
                            .padding(.horizontal, 24)
                        
                        // Live preview of the editor
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.textBackgroundColor))
                                .shadow(radius: 2)
                            
                            SimpleLineNumberView(
                                text: .constant("""
                                    // Sample code
                                    func hello() {
                                        // Hello, World!
                                        // 日本語のコメント
                                        return "こんにちは"
                                    }
                                    
                                    """),
                                font: fontManager.editorFont,
                                onScrollChange: nil
                            )
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .frame(width: 500, height: 600)
    }
}
#endif
