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
    let onQueueDrag: ((CGSize) -> Void)?
    let onQueueLongPress: (() -> Void)?
    let onTogglePin: () -> Void
    let onDelete: (() -> Void)?
    // ユーザカテゴリ変更/管理
    let onChangeCategory: ((UUID, Bool) async throws -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    let historyFont: Font
    let onOpenItem: (() -> Void)?
    let onSplitEditorIntoHistory: ((ClipItem) -> Void)?
    let hoverResetSignal: UUID
    let hoverCoordinator: HistoryHoverCoordinator
    private let displayContent: String

    @EnvironmentObject private var actionKeyMonitor: HistoryActionKeyMonitor
    @Environment(\.categoryPopoverChanged) private var presentationChanged
    @State private var isEditingCategories = false
    @State private var showingDetails = false
    @State private var isHovered = false
    @State private var popoverTask: DispatchWorkItem?
    @State private var windowPosition: Bool?
    @State private var currentAnchorView: NSView?
    @GestureState private var isQueueDragGestureActive = false
    @State private var hasStartedQueueDrag = false

    init(
        item: ClipItem,
        isSelected: Bool,
        isCurrentClipboardItem: Bool,
        queueBadge: Int?,
        isQueuePreviewed: Bool,
        isScrollLocked: Bool,
        onTap: @escaping () -> Void,
        onQueueDrag: ((CGSize) -> Void)? = nil,
        onQueueLongPress: (() -> Void)? = nil,
        onTogglePin: @escaping () -> Void,
        onDelete: (() -> Void)?,
        onChangeCategory: ((UUID, Bool) async throws -> Void)?,
        onOpenCategoryManager: (() -> Void)?,
        historyFont: Font,
        onOpenItem: (() -> Void)?,
        onSplitEditorIntoHistory: ((ClipItem) -> Void)?,
        hoverResetSignal: UUID,
        hoverCoordinator: HistoryHoverCoordinator
    ) {
        self.item = item
        self.isSelected = isSelected
        self.isCurrentClipboardItem = isCurrentClipboardItem
        self.queueBadge = queueBadge
        self.isQueuePreviewed = isQueuePreviewed
        self.isScrollLocked = isScrollLocked
        self.onTap = onTap
        self.onQueueDrag = onQueueDrag
        self.onQueueLongPress = onQueueLongPress
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
        self.onChangeCategory = onChangeCategory
        self.onOpenCategoryManager = onOpenCategoryManager
        self.historyFont = historyFont
        self.onOpenItem = onOpenItem
        self.onSplitEditorIntoHistory = onSplitEditorIntoHistory
        self.hoverResetSignal = hoverResetSignal
        self.hoverCoordinator = hoverCoordinator
        let preview = HistoryItemView.makeDisplayContent(from: item.content)
        self.displayContent = item.title ?? preview
    }

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
            baseView.contextMenu { contextMenuContent }
        }
        .sheet(isPresented: $showingDetails) { ClipDetailsView(item: item) }
        .onChange(of: hoverResetSignal) { _, _ in
            resetHoverState()
        }
        .onChange(of: isQueueDragGestureActive) { _, active in
            if !active { hasStartedQueueDrag = false }
        }
        .onChange(of: isScrollLocked) { _, locked in
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
                .gesture(selectionGesture)

            HistoryColumnsRow(showsQueue: queueBadge != nil) {
                queueBadgeView
            } pin: {
                pinButton
            } category: {
                categoryMenuView
            } content: {
                historyText
            } trailing: {
                deleteButton
            }
            .padding(.vertical, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var queueBadgeView: some View {
        if let queueBadge {
            let isActiveBadge = queueBadge > 0
            let badgeText = isActiveBadge ? "\(queueBadge)" : "-"
            let badgeBackground = isActiveBadge
                ? MainViewMetrics.HistoryQueueBadge.activeFill
                : MainViewMetrics.HistoryQueueBadge.inactiveFill
            let badgeForeground = isActiveBadge
                ? MainViewMetrics.HistoryQueueBadge.activeForeground
                : MainViewMetrics.HistoryQueueBadge.inactiveForeground

            Text(badgeText)
                .font(MainViewMetrics.HistoryQueueBadge.font)
                .foregroundColor(badgeForeground)
                .frame(
                    width: MainViewMetrics.HistoryColumns.rowControlSize,
                    height: MainViewMetrics.HistoryColumns.rowControlSize
                )
                .background(
                    Circle()
                        .fill(badgeBackground)
                )
                .frame(
                    width: MainViewMetrics.HistoryColumns.controlColumnWidth,
                    height: MainViewMetrics.HistoryColumns.controlColumnWidth,
                    alignment: .center
                )
                .contentShape(Circle())
                .gesture(selectionGesture)
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
            baseFill = AnyShapeStyle(Color.primary.opacity(0.05))
        } else if isQueuePreviewed {
            baseFill = AnyShapeStyle(Color.primary.opacity(0.035))
        } else {
            baseFill = AnyShapeStyle(Color.primary.opacity(isHoverActive ? 0.026 : 0))
        }

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(baseFill)
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
        .frame(
            width: MainViewMetrics.HistoryColumns.rowControlSize,
            height: MainViewMetrics.HistoryColumns.rowControlSize
        )
        .frame(
            width: MainViewMetrics.HistoryColumns.controlColumnWidth,
            height: MainViewMetrics.HistoryColumns.controlColumnWidth,
            alignment: .center
        )
        .contentShape(Circle())
        .onTapGesture {
            closePopover()
            onTogglePin()
        }
        .help(pinHelpText)
    }

    private var historyText: some View {
        let isLinkActive = actionKeyMonitor.isActionKeyActive && item.isActionable
        return HStack(spacing: 4) {
            if item.title != nil { titleBadge }
            Text(verbatim: displayContent)
                .underline(isLinkActive, color: linkColor)
        }
            .font(historyFont)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundColor(isLinkActive ? linkColor : MainViewMetrics.TextColor.primary)
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(selectionGesture)
    }

    private var selectionGesture: some Gesture {
        queueSelectionGesture
            .exclusively(before: TapGesture())
            .onEnded { value in
                hasStartedQueueDrag = false
                if case .second = value { handleTap() }
            }
    }

    private var queueSelectionGesture: AnyGesture<Void> {
        let drag = DragGesture(minimumDistance: 6)
            .updating($isQueueDragGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                guard !hasStartedQueueDrag else { return }
                closePopover()
                hasStartedQueueDrag = true
                onQueueDrag?(value.translation)
            }
        if let onQueueLongPress {
            return AnyGesture(
                LongPressGesture(minimumDuration: 0.5, maximumDistance: 6)
                    .onEnded { _ in
                        guard NSEvent.modifierFlags.isDisjoint(with: [.shift, .command, .option, .control]) else {
                            return
                        }
                        closePopover()
                        onQueueLongPress()
                    }
                    .exclusively(before: drag)
                    .map { _ in () }
            )
        }
        return AnyGesture(drag.map { _ in () })
    }

    private var titleBadge: some View {
        Text(verbatim: "Title")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(KippleButtonAppearance.inactivePillFill, in: RoundedRectangle(cornerRadius: 3))
            .fixedSize(horizontal: true, vertical: false)
    }

    private var deleteButton: some View {
        ZStack {
            if let onDelete = onDelete, isHoverActive && !item.isPinned {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(KippleButtonAppearance.inactiveForeground)
                    .frame(
                        width: MainViewMetrics.HistoryColumns.rowControlSize,
                        height: MainViewMetrics.HistoryColumns.rowControlSize
                    )
                    .contentShape(Circle())
                    .help(deleteHelpText)
                    .onTapGesture {
                        closePopover()
                        onDelete()
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .frame(
            width: MainViewMetrics.HistoryColumns.controlColumnWidth,
            height: MainViewMetrics.HistoryColumns.controlColumnWidth,
            alignment: .center
        )
    }

    private var pinHelpText: String {
        AppSettings.shared.localizedString(
            item.isPinned ? "Unpin item" : "Pin item",
            comment: "Tooltip for toggling pin state in history list"
        )
    }

    private var deleteHelpText: String {
        AppSettings.shared.localizedString(
            "Delete item",
            comment: "Tooltip for deleting a history item"
        )
    }

    static func makeDisplayContent(from content: String) -> String {
        if let newlineIndex = content.firstIndex(of: "\n") {
            return String(content[..<newlineIndex]) + "…"
        }
        return content
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
        guard !isEditingCategories else { return }
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
        KippleButtonAppearance.compactFill(isActive: item.isPinned)
    }

    var pinButtonIcon: String {
        item.isPinned ? "pin.fill" : "pin"
    }

    var pinButtonForeground: Color {
        KippleButtonAppearance.foreground(isActive: item.isPinned)
    }

    var pinButtonRotation: Double {
        item.isPinned ? 0 : -45
    }

    private var isHoverActive: Bool {
        isHovered && !isScrollLocked
    }

    var openMenuTitle: String {
        AppSettings.shared.localizedString(
            "Open",
            comment: "Context menu item to open a history entry"
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
        .frame(
            width: MainViewMetrics.HistoryColumns.controlColumnWidth,
            height: MainViewMetrics.HistoryColumns.controlColumnWidth,
            alignment: .center
        )
        .environment(\.categoryPopoverChanged, CategoryPopoverAction { id, presented in
            closePopover()
            isEditingCategories = presented
            presentationChanged(id, presented)
        })
    }

    @ViewBuilder
    var contextMenuContent: some View {
        Button("Item details") { closePopover(); showingDetails = true }
        Divider()
        if let onOpenItem, item.isActionable {
            Button {
                closePopover()
                onOpenItem()
            } label: {
                Label(openMenuTitle, systemImage: "arrow.up.right.square")
            }
        }
        if onSplitEditorIntoHistory != nil,
           item.isActionable && onOpenItem != nil {
            Divider()
        }
        if let onSplitEditorIntoHistory {
            Button {
                closePopover()
                onSplitEditorIntoHistory(item)
            } label: {
                Label {
                    Text("editor.splitCopy.menu")
                } icon: {
                    Image(systemName: "text.badge.plus")
                }
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
