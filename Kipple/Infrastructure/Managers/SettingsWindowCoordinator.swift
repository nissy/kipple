//
//  SettingsWindowCoordinator.swift
//  Kipple
//
//  Created by Codex on 2025/09/27.
//

import SwiftUI
import AppKit
import Combine

@MainActor
final class SettingsHostingController<Content: View>: NSHostingController<Content> {
    override func cancelOperation(_ sender: Any?) {
        view.window?.performClose(sender)
    }
}

@MainActor
final class SettingsToolbarController: NSObject, NSToolbarDelegate {
    private let viewModel: SettingsViewModel
    private weak var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private let appSettings = AppSettings.shared
    private var localizationCancellable: AnyCancellable?
    private let minimumContentSize = NSSize(width: 430, height: 300)
    private lazy var toolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsExtensionItems = false
        return toolbar
    }()

    private static let toolbarIdentifier = NSToolbar.Identifier("com.kipple.settings.toolbar")

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        super.init()
        bindToViewModel()
        localizationCancellable = appSettings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshLocalization()
                self.updateWindowSize(animated: true)
                DispatchQueue.main.async { [weak self] in
                    self?.updateWindowSize(animated: true)
                }
            }
    }

    func attach(to window: NSWindow) {
        self.window = window
        window.toolbar = toolbar
        toolbar.isVisible = false
        toolbar.selectedItemIdentifier = viewModel.selectedTab.toolbarIdentifier
        window.contentMinSize = minimumContentSize
        refreshLocalization()
        updateWindowSize(animated: false)
        DispatchQueue.main.async { [weak self] in
            self?.updateWindowSize(animated: false)
        }
    }

    private func bindToViewModel() {
        viewModel.$selectedTab
            .removeDuplicates()
            .sink { [weak self] tab in
                guard let self = self else { return }
                if self.toolbar.selectedItemIdentifier != tab.toolbarIdentifier {
                    self.toolbar.selectedItemIdentifier = tab.toolbarIdentifier
                }
                self.refreshLocalization()
                self.updateWindowSize(animated: true)
                DispatchQueue.main.async { [weak self] in
                    self?.updateWindowSize(animated: true)
                }
            }
            .store(in: &cancellables)
    }

    @objc
    private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = SettingsViewModel.Tab(toolbarIdentifier: sender.itemIdentifier) else { return }
        updateSelectionIfNeeded(to: tab)
    }

    private func updateSelectionIfNeeded(to tab: SettingsViewModel.Tab) {
        if viewModel.selectedTab != tab {
            viewModel.selectedTab = tab
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsViewModel.Tab.allToolbarIdentifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsViewModel.Tab.allToolbarIdentifiers
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsViewModel.Tab.allToolbarIdentifiers
    }

    func toolbar(_ toolbar: NSToolbar, didSelect itemIdentifier: NSToolbarItem.Identifier) {
        guard let tab = SettingsViewModel.Tab(toolbarIdentifier: itemIdentifier) else { return }
        updateSelectionIfNeeded(to: tab)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsViewModel.Tab(toolbarIdentifier: itemIdentifier) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let localizedTitle = appSettings.localizedString(tab.titleKey, comment: "Settings tab title")
        item.label = localizedTitle
        item.paletteLabel = localizedTitle
        item.toolTip = localizedTitle
        if let image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: localizedTitle) {
            item.image = image
        }
        item.target = self
        item.action = #selector(selectTab(_:))
        item.isBordered = true
        return item
    }

    func refreshLocalization() {
        guard let window else { return }
        toolbar.items.forEach { item in
            guard let tab = SettingsViewModel.Tab(toolbarIdentifier: item.itemIdentifier) else { return }
            let title = appSettings.localizedString(tab.titleKey, comment: "Settings tab title")
            item.label = title
            item.paletteLabel = title
            item.toolTip = title
            if let image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: title) {
                item.image = image
            }
        }
        updateWindowTitle()
    }

    private func updateWindowSize(animated: Bool) {
        guard let window = window else { return }
        guard let contentView = window.contentView else { return }

        contentView.layoutSubtreeIfNeeded()
        var targetSize = contentView.fittingSize
        targetSize.width = max(targetSize.width, minimumContentSize.width)
        targetSize.height = max(targetSize.height, minimumContentSize.height)

        let currentSize = window.frame.size
        guard abs(currentSize.width - targetSize.width) > 0.5 ||
                abs(currentSize.height - targetSize.height) > 0.5 else { return }

        window.setContentSize(targetSize)
    }

    private func updateWindowTitle() {
        guard let window else { return }
        let settingsTitle = appSettings.localizedString("Settings", comment: "Settings window title")
        window.title = settingsTitle
        window.subtitle = ""
    }
}

@MainActor
extension SettingsViewModel.Tab {
    static var allToolbarIdentifiers: [NSToolbarItem.Identifier] {
        Self.allCases.map { $0.toolbarIdentifier }
    }

    var toolbarIdentifier: NSToolbarItem.Identifier {
        switch self {
        case .general:
            return NSToolbarItem.Identifier("com.kipple.settings.general")
        case .editor:
            return NSToolbarItem.Identifier("com.kipple.settings.editor")
        case .clipboard:
            return NSToolbarItem.Identifier("com.kipple.settings.clipboard")
        case .permission:
            return NSToolbarItem.Identifier("com.kipple.settings.permission")
        }
    }

    init?(toolbarIdentifier: NSToolbarItem.Identifier) {
        switch toolbarIdentifier.rawValue {
        case "com.kipple.settings.general": self = .general
        case "com.kipple.settings.editor": self = .editor
        case "com.kipple.settings.clipboard": self = .clipboard
        case "com.kipple.settings.permission": self = .permission
        default: return nil
        }
    }
}
