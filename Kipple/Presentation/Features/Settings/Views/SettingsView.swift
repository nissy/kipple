//
//  SettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var fontManager = FontManager.shared
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var activeTab: SettingsViewModel.Tab

    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _activeTab = State(initialValue: viewModel.selectedTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tabContent
                .id(activeTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 560, alignment: .topLeading)
        .background(glassBackground)
        .animation(nil, value: activeTab)
        .onReceive(viewModel.$selectedTab) { newTab in
            if activeTab != newTab {
                withAnimation(.easeInOut(duration: 0.18)) {
                    activeTab = newTab
                }
            }
        }
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

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .general:
            GeneralSettingsView()
        case .editor:
            EditorSettingsView()
        case .clipboard:
            DataSettingsView()
        case .permission:
            PermissionsSettingsView()
        }
    }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(SettingsViewModel.Tab.allCases, id: \.self) { tab in
                SettingsToolbarButton(
                    tab: tab,
                    isSelected: tab == activeTab,
                    controlActiveState: controlActiveState
                ) {
                    guard activeTab != tab else { return }
                    viewModel.selectedTab = tab
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor).opacity(0.95),
                    Color(NSColor.windowBackgroundColor).opacity(0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var glassBackground: some View {
        Color(NSColor.windowBackgroundColor)
    }
}

private struct SettingsToolbarButton: View {
    let tab: SettingsViewModel.Tab
    let isSelected: Bool
    let controlActiveState: ControlActiveState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(borderColor, lineWidth: isSelected ? 1 : 0)
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(iconColor)
                    )

                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(labelColor)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(width: SettingsLayoutMetrics.toolbarButtonWidth)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(tab.title)
    }

    private var backgroundColor: Color {
        if isSelected {
            return tab.accentColor.opacity(controlActiveState == .inactive ? 0.12 : 0.16)
        } else {
            return Color.secondary.opacity(controlActiveState == .inactive ? 0.06 : 0.1)
        }
    }

    private var borderColor: Color {
        guard isSelected else { return Color.clear }
        return tab.accentColor.opacity(controlActiveState == .inactive ? 0.2 : 0.35)
    }

    private var iconColor: Color {
        isSelected ? tab.accentColor : Color.secondary
    }

    private var labelColor: Color {
        isSelected ? .primary : .secondary
    }
}

private struct GlassView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let isActive: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = isActive ? .active : .inactive
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .withinWindow
        nsView.state = isActive ? .active : .inactive
        nsView.isEmphasized = true
    }
}

// MARK: - Add Fallback Font Sheet
struct AddFallbackFontSheet: View {
    @Binding var selectedFont: String
    let availableFonts: [String]
    let onAdd: () -> Void
    let onCancel: () -> Void
    @Environment(\.controlActiveState) private var controlActiveState
    
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
        .background(
            ZStack {
                GlassView(
                    material: controlActiveState == .inactive ? .underWindowBackground : .menu,
                    isActive: controlActiveState != .inactive
                )
                .allowsHitTesting(false)
                LinearGradient(
                    colors: [
                        Color.white.opacity(controlActiveState == .inactive ? 0.64 : 0.82),
                        Color.white.opacity(controlActiveState == .inactive ? 0.56 : 0.74)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                Color.accentColor
                    .opacity(controlActiveState == .inactive ? 0.02 : 0.05)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
    }
}
