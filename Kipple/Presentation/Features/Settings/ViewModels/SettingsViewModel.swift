//
//  SettingsViewModel.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var selectedTab: Tab = .general
    @Published var showLaunchAtLoginError = false
    @Published var launchAtLoginErrorMessage = ""
    @Published var showingAddFallbackSheet = false
    @Published var selectedFallbackFont = ""
    @Published var availableFonts: [String] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupObservers()
        loadAvailableFonts()
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: NSNotification.Name("LaunchAtLoginError"))
            .sink { [weak self] notification in
                if let errorMessage = notification.userInfo?["error"] as? String {
                    self?.launchAtLoginErrorMessage = errorMessage
                    self?.showLaunchAtLoginError = true
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadAvailableFonts() {
        availableFonts = FontManager.availableMonospacedFonts()
    }
    
    func addFallbackFont() {
        let usedFonts = Set([FontManager.shared.editorSettings.primaryFontName] + 
                           FontManager.shared.editorSettings.fallbackFontNames)
        selectedFallbackFont = availableFonts.first { !usedFonts.contains($0) } ?? ""
        if !selectedFallbackFont.isEmpty {
            showingAddFallbackSheet = true
        }
    }
    
    func removeFallbackFont(at index: Int) {
        FontManager.shared.editorSettings.fallbackFontNames.remove(at: index)
    }

    enum Tab: Int, CaseIterable {
        case general
        case editor
        case clipboard

        var title: String {
            switch self {
            case .general: return "General"
            case .editor: return "Editor"
            case .clipboard: return "Clipboard"
            }
        }

        var symbolName: String {
            switch self {
            case .general: return "gear"
            case .editor: return "pencil"
            case .clipboard: return "doc.on.clipboard"
            }
        }

        var accentColor: Color {
            switch self {
            case .general: return .blue
            case .editor: return .green
            case .clipboard: return .orange
            }
        }
    }
}
