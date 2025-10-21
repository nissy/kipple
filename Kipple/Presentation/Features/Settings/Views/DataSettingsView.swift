//
//  DataSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import AppKit

struct DataSettingsView: View {
    @AppStorage("maxHistoryItems") private var maxHistoryItems = 300
    @AppStorage("maxPinnedItems") private var maxPinnedItems = 50
    @AppStorage("filterCategoryURL") private var filterCategoryURL = true
    @AppStorage("enableAutoClear") private var enableAutoClear = true
    @AppStorage("autoClearInterval") private var autoClearInterval = 10
    @AppStorage("actionClickModifiers") private var actionClickModifiers = Int(NSEvent.ModifierFlags.command.rawValue)
    @State private var showClearHistoryAlert = false
    @State private var showClearSuccessAlert = false
    @State private var clearedItemCount = 0
    @ObservedObject private var appSettings = AppSettings.shared
    
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
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                ClipboardFontSettingsView()

                // Action Click
                SettingsGroup("Open URI") {
                    SettingsRow(
                        label: "Modified click",
                        description: "Use modifier + click"
                    ) {
                        ModifierKeyPicker(selection: $actionClickModifiers)
                            .frame(width: 120)
                    }
                }

                // Categories management entry (moved from Settings to Manager)
                SettingsGroup("Categories") {
                    SettingsRow(label: "Manage Categories") {
                        ManageCategoriesButton()
                    }
                }
                
                // Auto-Clear Settings Section
                SettingsGroup("Auto Clipboard Clear") {
                    SettingsRow(label: "Enable Auto Clipboard Clear", isOn: $enableAutoClear)
                        .onChange(of: enableAutoClear) { _ in
                            updateAutoClearConfiguration()
                        }
                    
                    SettingsRow(label: "Clear interval") {
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
                
                // Storage Limits Section
                SettingsGroup("Storage Limits") {
                    SettingsRow(label: "Maximum history items") {
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
                            .onChange(of: maxHistoryItems) { newValue in
                                updateHistoryLimit(newValue)
                            }

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
                    
                    SettingsRow(label: "Maximum pinned items") {
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
                
                // Data Management Section
                SettingsGroup("Data Management") {
                    SettingsRow(
                        label: "Clear history",
                        description: "Remove all clipboard history items (pinned items stay)"
                    ) {
                        HStack(spacing: 10) {
                            Button(action: {
                                showClearHistoryAlert = true
                            }, label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 12))
                                    Text("Clear All History")
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    LinearGradient(
                                        colors: [Color.red, Color.red.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .cornerRadius(6)
                                .shadow(color: Color.red.opacity(0.25), radius: 1, y: 1)
                            })
                            .buttonStyle(PlainButtonStyle())
                            .disabled(clipboardService.history.isEmpty)

                            Spacer(minLength: 12)

                            VStack(alignment: .trailing, spacing: 2) {
                                let unpinnedCount = clipboardService.history.filter { !$0.isPinned }.count
                                let pinnedCount = clipboardService.history.filter { $0.isPinned }.count

                                if unpinnedCount > 0 {
                                    Text(localizedHistoryCountMessage(unpinnedCount))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                if pinnedCount > 0 {
                                    Text(localizedPinnedCountMessage(pinnedCount))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
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
            Text(clearHistoryConfirmationMessage(unpinnedCount: unpinnedCount, pinnedCount: pinnedCount))
        }
        .alert("History Cleared", isPresented: $showClearSuccessAlert) {
            Button("OK") { }
        } message: {
            Text(clearHistorySuccessMessage(count: clearedItemCount))
        }
    }
    
    private func clearHistory() {
        // 削除前の履歴アイテム数を記録（ピン留め以外）
        let unpinnedItems = clipboardService.history.filter { !$0.isPinned }
        clearedItemCount = unpinnedItems.count

        // 履歴をクリア（ピン留めアイテムは保持）
        Task {
            await clipboardService.clearHistory(keepPinned: true)

            // 成功アラートを表示
            await MainActor.run {
                showClearSuccessAlert = true
            }
        }
    }

    private func updateHistoryLimit(_ newLimit: Int) {
        // Update ModernClipboardService with new limit
        if let modernService = clipboardService as? ModernClipboardServiceAdapter {
            Task {
                await modernService.setMaxHistoryItems(newLimit)
            }
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
        if let modernService = clipboardService as? ModernClipboardServiceAdapter {
            Task { @MainActor in
                modernService.stopAutoClearTimer()
                if enableAutoClear {
                    modernService.startAutoClearTimer(minutes: autoClearInterval)
                }
            }
        }
    }

    private func localizedHistoryCountMessage(_ count: Int) -> String {
        appSettings.localizedFormat(
            "history.unpinnedCount",
            comment: "Shows the number of items currently in history",
            count
        )
    }

    private func localizedPinnedCountMessage(_ count: Int) -> String {
        appSettings.localizedFormat(
            "history.pinnedCount",
            comment: "Shows the number of pinned items",
            count
        )
    }

    private func clearHistoryConfirmationMessage(unpinnedCount: Int, pinnedCount: Int) -> String {
        var components: [String] = [
            appSettings.localizedFormat(
                "history.clear.deleteCount",
                comment: "Describes how many history items will be deleted",
                unpinnedCount
            )
        ]

        if pinnedCount > 0 {
            components.append(
                appSettings.localizedFormat(
                    "history.clear.pinnedPreserved",
                    comment: "Describes how many pinned items remain",
                    pinnedCount
                )
            )
        }

        components.append(
            appSettings.localizedString(
                "history.clear.cannotUndo",
                comment: "Warns that the action cannot be undone"
            )
        )

        return components.joined(separator: " ")
    }

    private func clearHistorySuccessMessage(count: Int) -> String {
        appSettings.localizedFormat(
            "history.clear.success",
            comment: "Summary after clearing history",
            count
        )
    }
}
