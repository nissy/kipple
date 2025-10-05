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
    let onTap: () -> Void
    let onTogglePin: () -> Void
    let onDelete: (() -> Void)?
    let onCategoryTap: (() -> Void)?
    // ユーザカテゴリ変更/管理
    let onChangeCategory: ((UUID?) -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    let historyFont: Font

    @State private var isHovered = false
    @State private var popoverTask: DispatchWorkItem?
    @State private var windowPosition: Bool?
    @State private var isScrolling = false
    @State private var currentAnchorView: NSView?
    @State private var isActionKeyActive = false
    @State private var flagsMonitor: Any?

    var body: some View {
        HoverTrackingView(content: rowContent) { hovering, anchor in
            currentAnchorView = anchor

            if isScrolling {
                isHovered = hovering
                if !hovering {
                    HistoryPopoverManager.shared.scheduleHide()
                }
                return
            }

            isHovered = hovering
            cancelPopoverTask()

            if hovering {
                if windowPosition == nil {
                    windowPosition = evaluateWindowPosition()
                }
                schedulePopoverPresentation(anchor: anchor)
            } else {
                HistoryPopoverManager.shared.scheduleHide()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.willStartLiveScrollNotification)) { _ in
            isScrolling = true
            HistoryPopoverManager.shared.scheduleHide()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didEndLiveScrollNotification)) { _ in
            isScrolling = false
            if isHovered, let anchor = currentAnchorView {
                schedulePopoverPresentation(anchor: anchor)
            }
        }
        .onDisappear {
            HistoryPopoverManager.shared.hide()
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
        }
        .onAppear {
            updateActionKeyActive()
            if flagsMonitor == nil {
                flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    updateActionKeyActive(with: event.modifierFlags)
                    return event
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
                pinButton
                categoryMenu
                historyText
                deleteButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isSelected ? AnyShapeStyle(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )) : AnyShapeStyle(Color(NSColor.quaternaryLabelColor).opacity(isHovered ? 0.5 : 0.2))
            )
            .overlay(
                isHovered && !isSelected ?
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1) : nil
            )
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
                .frame(width: 24, height: 24)

            Image(systemName: pinButtonIcon)
                .foregroundColor(pinButtonForeground)
                .font(.system(size: 11, weight: .medium))
                .rotationEffect(.degrees(pinButtonRotation))
        }
        .frame(width: 24, height: 24)
        .contentShape(Circle())
        .onTapGesture {
            closePopover()
            onTogglePin()
        }
    }

    @ViewBuilder
    private var categoryIcon: some View {
        if item.isActionable {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                    .frame(width: 24, height: 24)

                Image(systemName: item.category.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
            .onTapGesture { handleTap() }
            .help(actionHelpText)
        } else if let onCategoryTap = onCategoryTap {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                    .frame(width: 24, height: 24)

                Image(systemName: item.category.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
            .onTapGesture {
                closePopover()
                onCategoryTap()
            }
            .help("「\(item.category.rawValue)」でフィルタ")
        } else {
            Image(systemName: item.category.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                )
        }
    }

    private var historyText: some View {
        let isLinkActive = isActionKeyActive && item.isActionable
        return Text(getDisplayContent())
            .font(historyFont)
            .lineLimit(1)
            .truncationMode(.tail)
            .underline(isLinkActive, color: linkColor)
            .foregroundColor(isLinkActive ? linkColor : (isSelected ? .white : .primary))
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if let onDelete = onDelete, isHovered && !isScrolling && !item.isPinned {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .contentShape(Circle())
                .onTapGesture {
                    closePopover()
                    onDelete()
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        }
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
            if isHovered && !isScrolling {
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
}

// MARK: - Category Menu
private extension HistoryItemView {
    @ViewBuilder
    var categoryMenu: some View {
        Menu(content: {
            Button(role: .none) {
                let noneId = UserCategoryStore.shared.noneCategoryId()
                onChangeCategory?(noneId)
            } label: {
                Label("None", systemImage: "tag")
            }
            Divider()
            ForEach(UserCategoryStore.shared.userDefined()) { cat in
                Button(action: { onChangeCategory?(cat.id) }) {
                    Label(cat.name, systemImage: UserCategoryStore.shared.iconName(for: cat))
                }
            }
            Divider()
            Button("Manage Categories…") { onOpenCategoryManager?() }
        }, label: {
            let current = UserCategoryStore.shared.category(id: item.userCategoryId)
            let iconName = current.map { UserCategoryStore.shared.iconName(for: $0) } ?? "tag"
            ZStack {
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                    .frame(width: 36, height: 24)

                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 16, height: 16)
            }
        })
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(width: 35, alignment: .leading)
    }
}

// MARK: - Action helpers
private extension HistoryItemView {
    var linkColor: Color { Color(NSColor.linkColor) }

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

    func updateActionKeyActive(with flags: NSEvent.ModifierFlags? = nil) {
        let requiredBase = NSEvent.ModifierFlags(rawValue: UInt(AppSettings.shared.actionClickModifiers))
        let required = requiredBase.intersection(.deviceIndependentFlagsMask)
        let current = (flags ?? NSEvent.modifierFlags).intersection(.deviceIndependentFlagsMask)
        guard !required.isEmpty else {
            isActionKeyActive = false
            return
        }
        isActionKeyActive = (current == required)
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
        return "\(key)+Click to \(item.actionTitle ?? "Open")"
    }
}
