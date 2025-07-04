//
//  SettingsViewModel.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    @Published var selectedTab = 0
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
    
    var tabIcon: String {
        switch selectedTab {
        case 0: return "gear"
        case 1: return "pencil"
        case 2: return "doc.on.clipboard"
        default: return "gear"
        }
    }
    
    var tabColor: Color {
        switch selectedTab {
        case 0: return .blue
        case 1: return .green
        case 2: return .orange
        default: return .blue
        }
    }
    
    var tabTitle: String {
        switch selectedTab {
        case 0: return "General"
        case 1: return "Editor"
        case 2: return "Clipboard"
        default: return "General"
        }
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
}
