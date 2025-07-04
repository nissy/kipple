//
//  DataSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI

struct DataSettingsView: View {
    @AppStorage("maxHistoryItems") private var maxHistoryItems = 100
    @AppStorage("maxPinnedItems") private var maxPinnedItems = 10
    @State private var showClearHistoryAlert = false
    @State private var showClearSuccessAlert = false
    @State private var clearedItemCount = 0
    
    private let clipboardService = ClipboardService.shared
    
    var body: some View {
        VStack(spacing: 14) {
            // Font Settings
            ClipboardFontSettingsView()
            
            Divider()
                .padding(.vertical, 8)
            
            // Storage Limits Section
            SettingsSection(
                icon: "externaldrive",
                iconColor: .orange,
                title: "Storage Limits"
            ) {
                VStack(spacing: 14) {
                    // Maximum history items
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Maximum History Items:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            
                            TextField(
                                "",
                                value: Binding(
                                    get: { Double(maxHistoryItems) },
                                    set: { maxHistoryItems = Int($0) }
                                ),
                                formatter: NumberFormatter()
                            )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            
                            Stepper(
                                "",
                                value: Binding(
                                    get: { Double(maxHistoryItems) },
                                    set: { maxHistoryItems = Int($0) }
                                ),
                                in: 10...1000,
                                step: 10
                            )
                                .labelsHidden()
                            
                            Spacer()
                        }
                        
                        Text("Maximum number of clipboard history items to keep")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    // Maximum pinned items
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Maximum Pinned Items:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            
                            TextField(
                                "",
                                value: Binding(
                                    get: { Double(maxPinnedItems) },
                                    set: { maxPinnedItems = Int($0) }
                                ),
                                formatter: NumberFormatter()
                            )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            
                            Stepper(
                                "",
                                value: Binding(
                                    get: { Double(maxPinnedItems) },
                                    set: { maxPinnedItems = Int($0) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                                .labelsHidden()
                            
                            Spacer()
                        }
                        
                        Text("Maximum number of items that can be pinned")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Data Management Section
            SettingsSection(
                icon: "trash",
                iconColor: .red,
                title: "Data Management"
            ) {
                VStack(spacing: 14) {
                    // Clear History
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clear Clipboard History")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        
                        HStack {
                            Button(action: {
                                showClearHistoryAlert = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 12))
                                    Text("Clear All History")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    LinearGradient(
                                        colors: [Color.red, Color.red.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .cornerRadius(6)
                                .shadow(color: Color.red.opacity(0.3), radius: 2, y: 1)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(clipboardService.history.isEmpty)
                            
                            Spacer()
                            
                            // アイテム数の表示
                            VStack(alignment: .trailing, spacing: 2) {
                                let unpinnedCount = clipboardService.history.filter { !$0.isPinned }.count
                                let pinnedCount = clipboardService.history.filter { $0.isPinned }.count
                                
                                if unpinnedCount > 0 {
                                    Text("\(unpinnedCount) items in history")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                if pinnedCount > 0 {
                                    Text("\(pinnedCount) pinned items")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Text("Permanently remove all clipboard history items")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .alert("Clear Clipboard History?", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear History", role: .destructive) {
                clearHistory()
            }
        } message: {
            let unpinnedCount = clipboardService.history.filter { !$0.isPinned }.count
            let pinnedCount = clipboardService.history.filter { $0.isPinned }.count
            
            let message = if pinnedCount > 0 {
                """
                This will permanently delete \(unpinnedCount) history item\(unpinnedCount == 1 ? "" : "s"). \
                Your \(pinnedCount) pinned item\(pinnedCount == 1 ? "" : "s") will be preserved. \
                This action cannot be undone.
                """
            } else {
                """
                This will permanently delete \(unpinnedCount) history item\(unpinnedCount == 1 ? "" : "s"). \
                This action cannot be undone.
                """
            }
            
            Text(message)
        }
        .alert("History Cleared", isPresented: $showClearSuccessAlert) {
            Button("OK") { }
        } message: {
            let itemText = "\(clearedItemCount) item\(clearedItemCount == 1 ? "" : "s")"
            Text("\(itemText) successfully removed from clipboard history.")
        }
    }
    
    private func clearHistory() {
        // 削除前の履歴アイテム数を記録（ピン留め以外）
        let unpinnedItems = clipboardService.history.filter { !$0.isPinned }
        clearedItemCount = unpinnedItems.count
        
        // 履歴をクリア（ピン留めアイテムは保持）
        clipboardService.clearAllHistory()
        
        // 成功アラートを表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showClearSuccessAlert = true
        }
    }
}
