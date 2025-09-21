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
    @AppStorage("filterCategoryURL") private var filterCategoryURL = true
    @AppStorage("filterCategoryEmail") private var filterCategoryEmail = true
    @AppStorage("filterCategoryCode") private var filterCategoryCode = true
    @AppStorage("filterCategoryFilePath") private var filterCategoryFilePath = true
    @AppStorage("filterCategoryShortText") private var filterCategoryShortText = true
    @AppStorage("filterCategoryLongText") private var filterCategoryLongText = true
    @AppStorage("filterCategoryGeneral") private var filterCategoryGeneral = true
    @AppStorage("filterCategoryKipple") private var filterCategoryKipple = true
    @AppStorage("enableAutoClear") private var enableAutoClear = false
    @AppStorage("autoClearInterval") private var autoClearInterval = 10
    @State private var showClearHistoryAlert = false
    @State private var showClearSuccessAlert = false
    @State private var clearedItemCount = 0
    
    private let clipboardService: any ClipboardServiceProtocol
    
    @MainActor
    init(clipboardService: (any ClipboardServiceProtocol)? = nil) {
        if let service = clipboardService {
            self.clipboardService = service
        } else {
            self.clipboardService = ClipboardServiceProvider.resolve()
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Font Settings
                ClipboardFontSettingsView()
                
                // Category Filter Settings Section
                SettingsGroup("Category Filter Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose which categories can be filtered in the history view")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                        
                        VStack(spacing: 0) {
                            SettingsRow(label: "URL", isOn: $filterCategoryURL)
                            SettingsRow(label: "Email", isOn: $filterCategoryEmail)
                            SettingsRow(label: "Code", isOn: $filterCategoryCode)
                            SettingsRow(label: "File Path", isOn: $filterCategoryFilePath)
                            SettingsRow(label: "Short Text", isOn: $filterCategoryShortText)
                            SettingsRow(label: "Long Text", isOn: $filterCategoryLongText)
                            SettingsRow(label: "General", isOn: $filterCategoryGeneral)
                            SettingsRow(label: "Kipple", isOn: $filterCategoryKipple)
                        }
                    }
                }
                
                // Auto-Clear Settings Section
                SettingsGroup("Auto-Clear") {
                    VStack(spacing: 0) {
                        SettingsRow(label: "Enable Auto-Clear", isOn: $enableAutoClear)
                            .onChange(of: enableAutoClear) { _ in
                                updateAutoClearConfiguration()
                            }
                        
                        SettingsRow(
                            label: "Clear Interval",
                            description: "Automatically clear system clipboard content after this duration"
                        ) {
                            HStack {
                                TextField(
                                    "",
                                    value: Binding(
                                        get: { Double(autoClearInterval) },
                                        set: { autoClearInterval = Int(max(1, min(1440, $0))) }
                                    ),
                                    formatter: makeNumberFormatter(minimum: 1, maximum: 1440)
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .disabled(!enableAutoClear)
                                
                                Text("minutes")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                Stepper(
                                    "",
                                    value: Binding(
                                        get: { Double(autoClearInterval) },
                                        set: { autoClearInterval = Int($0) }
                                    ),
                                    in: 1...1440,
                                    step: 1
                                )
                                .labelsHidden()
                                .disabled(!enableAutoClear)
                            }
                        }
                        .onChange(of: autoClearInterval) { _ in
                            updateAutoClearConfiguration()
                        }
                    }
                }
                
                // Storage Limits Section
                SettingsGroup("Storage Limits") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            label: "Maximum History Items",
                            description: "Maximum number of clipboard history items to keep"
                        ) {
                            HStack {
                                TextField(
                                    "",
                                    value: Binding(
                                        get: { Double(maxHistoryItems) },
                                        set: { maxHistoryItems = Int(max(10, min(1000, $0))) }
                                    ),
                                    formatter: makeNumberFormatter(minimum: 10, maximum: 1000)
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
                            }
                        }
                        
                        SettingsRow(
                            label: "Maximum Pinned Items",
                            description: "Maximum number of items that can be pinned"
                        ) {
                            HStack {
                                TextField(
                                    "",
                                    value: Binding(
                                        get: { Double(maxPinnedItems) },
                                        set: { maxPinnedItems = Int(max(1, min(100, $0))) }
                                    ),
                                    formatter: makeNumberFormatter(minimum: 1, maximum: 100)
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
                            }
                        }
                    }
                }
                
                // Data Management Section
                SettingsGroup("Data Management") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Permanently remove all clipboard history items")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                        
                        HStack {
                            Button(action: {
                                showClearHistoryAlert = true
                            }, label: {
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
                            })
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
                    }
                }
            }
            .padding(20)
        }
        .task {
            updateAutoClearConfiguration()
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
    
    private func makeNumberFormatter(minimum: Double, maximum: Double) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = NSNumber(value: minimum)
        formatter.maximum = NSNumber(value: maximum)
        formatter.generatesDecimalNumbers = false
        formatter.allowsFloats = false
        return formatter
    }

    private func updateAutoClearConfiguration() {
        if let legacyService = clipboardService as? ClipboardService {
            legacyService.updateAutoClearTimer()
        } else if #available(macOS 13.0, *), let modernService = clipboardService as? ModernClipboardServiceAdapter {
            Task { @MainActor in
                modernService.stopAutoClearTimer()
                if enableAutoClear {
                    modernService.startAutoClearTimer(minutes: autoClearInterval)
                }
            }
        }
    }
}
