//
//  SettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var fontManager = FontManager.shared
    
    var body: some View {
        NavigationView {
            sidebar
            contentArea
        }
        .frame(width: 620, height: 590)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $viewModel.showingAddFallbackSheet) {
            AddFallbackFontSheet(
                selectedFont: $viewModel.selectedFallbackFont,
                availableFonts: viewModel.availableFonts,
                onAdd: {
                    if !viewModel.selectedFallbackFont.isEmpty {
                        fontManager.editorSettings.fallbackFontNames.append(viewModel.selectedFallbackFont)
                    }
                    viewModel.showingAddFallbackSheet = false
                },
                onCancel: {
                    viewModel.showingAddFallbackSheet = false
                }
            )
        }
        .alert("Launch at Login Error", isPresented: $viewModel.showLaunchAtLoginError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.launchAtLoginErrorMessage)
        }
    }
    
    // MARK: - Sidebar
    private var sidebar: some View {
        List {
            SettingsSidebarItem(
                title: "General",
                icon: "gear",
                color: .blue,
                isSelected: viewModel.selectedTab == 0
            ) {
                viewModel.selectedTab = 0
            }
            
            SettingsSidebarItem(
                title: "Editor",
                icon: "pencil",
                color: .green,
                isSelected: viewModel.selectedTab == 1
            ) {
                viewModel.selectedTab = 1
            }
            
            SettingsSidebarItem(
                title: "Clipboard",
                icon: "doc.on.clipboard",
                color: .orange,
                isSelected: viewModel.selectedTab == 2
            ) {
                viewModel.selectedTab = 2
            }
        }
        .listStyle(SidebarListStyle())
        .frame(width: 170)
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Content Area
    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content Header
            HStack {
                Image(systemName: viewModel.tabIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(viewModel.tabColor)
                
                Text(viewModel.tabTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            Divider()
            
            // Tab Content
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case 0:
            GeneralSettingsView()
        case 1:
            EditorSettingsView()
        case 2:
            DataSettingsView()
        default:
            GeneralSettingsView()
        }
    }
}

// MARK: - Add Fallback Font Sheet
struct AddFallbackFontSheet: View {
    @Binding var selectedFont: String
    let availableFonts: [String]
    let onAdd: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.indigo, Color.indigo.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                        .shadow(color: Color.indigo.opacity(0.3), radius: 4, y: 2)
                    
                    Image(systemName: "textformat")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("Add Fallback Font")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Divider()
            
            // Font Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Select a font to add as fallback")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $selectedFont) {
                    let usedFonts = Set([FontManager.shared.editorSettings.primaryFontName] +
                                        FontManager.shared.editorSettings.fallbackFontNames)
                    ForEach(availableFonts.filter { !usedFonts.contains($0) }, id: \.self) { fontName in
                        Text(fontName)
                            .tag(fontName)
                            .font(.system(size: 12))
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity)
            }
            
            Spacer()
            
            // Buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add Font", action: onAdd)
                    .keyboardShortcut(.return)
                    .disabled(selectedFont.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360, height: 220)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
