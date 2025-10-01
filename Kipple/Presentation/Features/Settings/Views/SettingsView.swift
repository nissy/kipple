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
            tabContent
                .id(activeTab)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .animation(nil, value: activeTab)
        .onReceive(viewModel.$selectedTab) { newTab in
            if activeTab != newTab {
                activeTab = newTab
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(minWidth: 480, alignment: .topLeading)
        .background(glassBackground)
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
        }
    }

    private var glassBackground: some View {
        Color(NSColor.windowBackgroundColor)
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
