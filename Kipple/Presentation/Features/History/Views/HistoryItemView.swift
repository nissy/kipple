//
//  HistoryItemView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI
import AppKit

struct HistoryItemView: View {
    let item: ClipItem
    let isSelected: Bool
    let isCurrentClipboardItem: Bool
    let queueBadge: Int?
    let isQueuePreviewed: Bool
    let isScrollLocked: Bool
    let onTap: () -> Void
    let onTogglePin: () -> Void
    let onDelete: (() -> Void)?
    let onCategoryTap: (() -> Void)?
    // ユーザカテゴリ変更/管理
    let onChangeCategory: ((UUID?) -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    let historyFont: Font
    let onOpenItem: (() -> Void)?
    let onInsertToEditor: (() -> Void)?
    let hoverResetSignal: UUID

    @ObservedObject private var appSettings = AppSettings.shared
    @EnvironmentObject private var hoverCoordinator: HistoryHoverCoordinator
    @EnvironmentObject private var actionKeyMonitor: HistoryActionKeyMonitor
    @State private var isHovered = false
    @State private var popoverTask: DispatchWorkItem?
    @State private var windowPosition: Bool?
    @State private var currentAnchorView: NSView?

    var body: some View {
        let baseView = HoverTrackingView(content: rowContent, onHover: { hovering, anchor in
            currentAnchorView = anchor
            handleHoverChange(hovering, anchor: anchor)
        }, isScrollLocked: isScrollLocked)
        .onDisappear {
            HistoryPopoverManager.shared.hide()
            currentAnchorView = nil
            hoverCoordinator.clearHover(ifMatches: item.id)
        }

        return Group {
            if hasContextMenuActions {
                baseView.contextMenu { contextMenuContent }
            } else {
                baseView
            }
        }
        .onChange(of: hoverResetSignal) { _ in
            resetHoverState()
        }
        .onChange(of: isScrollLocked) { locked in
            if locked {
                if isHovered {
                    isHovered = false
                }
                cancelPopoverTask()
                HistoryPopoverManager.shared.scheduleHide()
            } else if isHovered, let anchor = currentAnchorView {
                schedulePopoverPresentation(anchor: anchor)
            }
        }
        .onReceive(hoverCoordinator.$hoveredItemID) { hoveredID in
            let shouldHover = hoveredID == item.id
            if isHovered != shouldHover {
                isHovered = shouldHover
                if shouldHover, !isScrollLocked, let anchor = currentAnchorView {
                    schedulePopoverPresentation(anchor: anchor)
                } else {
                    cancelPopoverTask()
                    HistoryPopoverManager.shared.scheduleHide()
                }
            }
        }
    }

    private var rowContent: some View {
        ZStack {
            backgroundView
                .contentShape(Rectangle())
                .onTapGesture { handleTap() }

            HStack(spacing: 8) {
                queueBadgeView
                pinButton
                categoryMenuView
                historyText
                deleteButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var queueBadgeView: some View {
        if let queueBadge {
            let isActiveBadge = queueBadge > 0
            let badgeText = isActiveBadge ? "\(queueBadge)" : "-"
            let badgeBackground = isActiveBadge ? Color.accentColor : Color.secondary.opacity(0.1)
            let badgeForeground = isActiveBadge ? Color.white : Color.secondary

            Text(badgeText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(badgeForeground)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(badgeBackground)
                )
                .contentShape(Circle())
                .help(
                    Text(
                        String(
                            format: NSLocalizedString(
                                "Queue position %d",
                                comment: "Tooltip showing queue badge position"
                            ),
                            queueBadge
                        )
                    )
                )
        }
    }

    private var backgroundView: some View {
        let baseFill: AnyShapeStyle
        if isSelected {
            baseFill = AnyShapeStyle(LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        } else if isQueuePreviewed {
            baseFill = AnyShapeStyle(Color.accentColor.opacity(0.25))
        } else {
            baseFill = AnyShapeStyle(Color(NSColor.quaternaryLabelColor).opacity(isHoverActive ? 0.5 : 0.2))
        }

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(baseFill)
            .overlay {
                if isHoverActive && !isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                } else if isQueuePreviewed && !isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                }
            }
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                radius: isSelected ? 8 : 0,
                y: isSelected ? 4 : 0
            )
    }

    private var pinButton: some View {
        ZStack {
            Circle()
                .fill(pinButtonBackground)
            Image(systemName: pinButtonIcon)
                .foregroundColor(pinButtonForeground)
                .font(.system(size: 10, weight: .medium))
                .rotationEffect(.degrees(pinButtonRotation))
        }
        .frame(width: 22, height: 22)
        .contentShape(Circle())
        .onTapGesture {
            closePopover()
            onTogglePin()
        }
        .help(pinHelpText)
    }

    @ViewBuilder
    private var categoryIcon: some View {
        if item.isActionable {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                    .frame(width: 22, height: 22)
                Image(systemName: item.category.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
            .onTapGesture { handleTap() }
            .help(actionHelpText)
        } else if let onCategoryTap = onCategoryTap {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                    .frame(width: 22, height: 22)
                Image(systemName: item.category.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
            .onTapGesture {
                closePopover()
                onCategoryTap()
            }
            .help(
                Text(
                    String(
                        format: NSLocalizedString(
                            "Filter by “%@”",
                            comment: "Filter tooltip with category name"
                        ),
                        item.category.localizedName
                    )
                )
            )
        } else {
            Image(systemName: item.category.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                )
        }
    }

    private var historyText: some View {
        let isLinkActive = actionKeyMonitor.isActionKeyActive && item.isActionable
        return Text(getDisplayContent())
            .font(historyFont)
            .lineLimit(1)
            .truncationMode(.tail)
            .underline(isLinkActive, color: linkColor)
            .foregroundColor(isLinkActive ? linkColor : (isSelected ? .white : .primary))
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if let onDelete = onDelete, isHoverActive && !item.isPinned {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .contentShape(Circle())
                .help(deleteHelpText)
                .onTapGesture {
                    closePopover()
                    onDelete()
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        }
    }

    private var pinHelpText: String {
        appSettings.localizedString(
            item.isPinned ? "Unpin item" : "Pin item",
            comment: "Tooltip for toggling pin state in history list"
        )
    }

    private var deleteHelpText: String {
        appSettings.localizedString(
            "Delete item",
            comment: "Tooltip for deleting a history item"
        )
    }

    private func getDisplayContent() -> String {
        if let newlineIndex = item.content.firstIndex(of: "\n") {
            return String(item.content[..<newlineIndex]) + "…"
        }
        return item.content
    }

    private func evaluateWindowPosition() -> Bool {
        guard let mainWindow = NSApp.windows.first(where: { window in
            window.isVisible && window.contentViewController != nil
        }) else {
            return true
        }

        guard let currentScreen = mainWindow.screen ?? NSScreen.main else {
            return true
        }

        let screenCenter = currentScreen.frame.midX
        return mainWindow.frame.midX < screenCenter
    }

    private func schedulePopoverPresentation(anchor: NSView) {
        cancelPopoverTask()
        let workItem = DispatchWorkItem {
            if isHovered && !isScrollLocked {
                let trailing = windowPosition ?? true
                HistoryPopoverManager.shared.show(item: item, from: anchor, trailingEdge: trailing)
            }
        }
        popoverTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func cancelPopoverTask() {
        popoverTask?.cancel()
        popoverTask = nil
    }

    private func closePopover() {
        cancelPopoverTask()
        HistoryPopoverManager.shared.hide()
    }

    private func resetHoverState() {
        if isHovered {
            isHovered = false
        }
        hoverCoordinator.clearHover(ifMatches: item.id)
        currentAnchorView = nil
        cancelPopoverTask()
        HistoryPopoverManager.shared.hide()
    }

    // MARK: - Pin helper properties
    var pinButtonBackground: Color {
        item.isPinned ? Color.accentColor : Color.secondary.opacity(0.1)
    }

    var pinButtonIcon: String {
        item.isPinned ? "pin.fill" : "pin"
    }

    var pinButtonForeground: Color {
        item.isPinned ? .white : .secondary
    }

    var pinButtonRotation: Double {
        item.isPinned ? 0 : -45
    }

    private var isHoverActive: Bool {
        isHovered && !isScrollLocked
    }

    var openMenuTitle: String {
        appSettings.localizedString(
            "Open",
            comment: "Context menu item to open a history entry"
        )
    }

    var insertMenuTitle: String {
        appSettings.localizedString(
            "Insert into Editor",
            comment: "Context menu item to insert history entry into the editor"
        )
    }
}

// MARK: - Action helpers
private extension HistoryItemView {
    var categoryMenuView: some View {
        HistoryCategoryMenu(
            item: item,
            isSelected: isSelected,
            onChangeCategory: onChangeCategory,
            onOpenCategoryManager: onOpenCategoryManager
        )
    }

    var hasContextMenuActions: Bool {
        (item.isActionable && onOpenItem != nil) || onInsertToEditor != nil
    }

    @ViewBuilder
    var contextMenuContent: some View {
        if let onOpenItem, item.isActionable {
            Button {
                closePopover()
                onOpenItem()
            } label: {
                Label(openMenuTitle, systemImage: "arrow.up.right.square")
            }
        }
        if let onInsertToEditor {
            Button {
                closePopover()
                onInsertToEditor()
            } label: {
                Label(insertMenuTitle, systemImage: "square.and.pencil")
            }
        }
    }

    var linkColor: Color { Color(NSColor.linkColor) }

    func handleHoverChange(_ hovering: Bool, anchor: NSView) {
        if isScrollLocked {
            hoverCoordinator.clearHover(ifMatches: item.id)
            cancelPopoverTask()
            HistoryPopoverManager.shared.scheduleHide()
            return
        }

        if hovering {
            hoverCoordinator.setHovered(itemID: item.id)
            if windowPosition == nil {
                windowPosition = evaluateWindowPosition()
            }
            schedulePopoverPresentation(anchor: anchor)
        } else {
            hoverCoordinator.clearHover(ifMatches: item.id)
            HistoryPopoverManager.shared.scheduleHide()
        }
    }

    func handleTap() {
        closePopover()
        let current = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let requiredBase = NSEvent.ModifierFlags(rawValue: UInt(AppSettings.shared.actionClickModifiers))
        let required = requiredBase.intersection(.deviceIndependentFlagsMask)

        if required.isEmpty {
            onTap()
            return
        }

        if item.isActionable && current == required {
            item.performAction()
        } else {
            onTap()
        }
    }

    var actionHelpText: String {
        guard item.isActionable else { return "" }
        let required = NSEvent.ModifierFlags(rawValue: UInt(AppSettings.shared.actionClickModifiers))
        let key: String
        switch required {
        case .command: key = "⌘"
        case .option: key = "⌥"
        case .control: key = "⌃"
        case .shift: key = "⇧"
        default: key = "⌘"
        }
        let actionTitle = item.actionTitle ?? NSLocalizedString("Open", comment: "Default action title")
        return String(
            format: NSLocalizedString(
                "%@+Click to %@",
                comment: "Modifier click instruction with action title"
            ),
            key,
            actionTitle
        )
    }
}
