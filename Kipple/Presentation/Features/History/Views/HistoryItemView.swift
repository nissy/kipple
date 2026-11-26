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
    let onDelete: (() -> Void)?
    // ユーザカテゴリ変更/管理
    let onChangeCategory: ((ClipCategoryChange) async throws -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    let historyFont: Font
    let onOpenItem: (() -> Void)?
    let onSplitEditorIntoHistory: ((ClipItem) -> Void)?
    let hoverResetSignal: UUID
    let hoverCoordinator: HistoryHoverCoordinator
    private let displayContent: String

    @EnvironmentObject private var actionKeyMonitor: HistoryActionKeyMonitor
    @ObservedObject private var desktopNotes = DesktopNoteWindowCoordinator.shared
    @Environment(\.categoryPopoverChanged) private var presentationChanged
    @Environment(\.openHistoryItemEditor) private var openHistoryItemEditor
    @State private var isEditingCategories = false
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
        onDelete: (() -> Void)?,
        onChangeCategory: ((ClipCategoryChange) async throws -> Void)?,
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
            if let anchor = currentAnchorView {
                HistoryPopoverManager.shared.hide(ifAnchoredTo: anchor)
            }
            currentAnchorView = nil
            hoverCoordinator.clearHover(ifMatches: item.id)
        }

        return Group {
            baseView.contextMenu { contextMenuContent }
        }
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
                if !shouldHover {
                    cancelPopoverTask()
                    if let anchor = currentAnchorView {
                        HistoryPopoverManager.shared.scheduleHide(ifAnchoredTo: anchor)
                    }
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
            } content: {
                historyText
            } pin: {
                desktopNoteButton
            } category: {
                categoryMenuView
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
            baseFill = AnyShapeStyle(Color.primary.opacity(isHoverActive ? 0.04 : 0.018))
        }

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(baseFill)
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

    private var desktopNoteButton: some View {
        let isPosted = desktopNotes.isPosted(item.id)
        let label = Text(LocalizedStringKey(isPosted ? "Remove Desktop Note" : "Post to Desktop"))

        return Button {
            closePopover()
            let screen = currentAnchorView?.window?.screen
            Task { await desktopNotes.toggle(item.id, on: screen) }
        } label: {
            Image(systemName: isPosted ? "pin.fill" : "pin")
                .font(MainViewMetrics.HistoryFilterIcon.defaultFont)
                .foregroundStyle(KippleButtonAppearance.foreground(isActive: isPosted))
                .rotationEffect(.degrees(isPosted ? 0 : -45))
                .frame(width: MainViewMetrics.HistoryColumns.rowControlSize,
                       height: MainViewMetrics.HistoryColumns.rowControlSize)
                .background(KippleButtonAppearance.compactFill(isActive: isPosted), in: Circle())
                .frame(width: MainViewMetrics.HistoryColumns.controlColumnWidth,
                       height: MainViewMetrics.HistoryColumns.controlColumnWidth)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    static func makeDisplayContent(from content: String) -> String {
        if let newlineIndex = content.firstIndex(of: "\n") {
            return String(content[..<newlineIndex]) + "…"
        }
        return content
    }

    private func schedulePopoverPresentation(anchor: NSView, after delay: TimeInterval = 0.3) {
        guard !isEditingCategories else { return }
        cancelPopoverTask()
        let workItem = DispatchWorkItem {
            if isHovered && !isScrollLocked {
                let trailing = windowPosition ?? true
                HistoryPopoverManager.shared.show(item: item, from: anchor, trailingEdge: trailing)
            }
        }
        popoverTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
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
        .environment(\.categoryPopoverChanged, CategoryPopoverAction { id, presented in
            closePopover()
            isEditingCategories = presented
            presentationChanged(id, presented)
        })
    }

    @ViewBuilder
    var contextMenuContent: some View {
        Button("Edit Item") {
            closePopover()
            openHistoryItemEditor(item)
        }
        if let onOpenItem, item.isActionable {
            Divider()
            Button {
                closePopover()
                onOpenItem()
            } label: {
                Label(openMenuTitle, systemImage: "arrow.up.right.square")
            }
        }
        if let onSplitEditorIntoHistory {
            Divider()
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
        if let onDelete, !item.hasCustomCategory, !desktopNotes.isPosted(item.id) {
            Divider()
            Button("Delete from History", role: .destructive) {
                closePopover()
                onDelete()
            }
        }
    }

    var linkColor: Color { Color(NSColor.linkColor) }

    func handleHoverChange(_ hovering: Bool, anchor: NSView) {
        if isScrollLocked {
            hoverCoordinator.clearHover(ifMatches: item.id)
            cancelPopoverTask()
            HistoryPopoverManager.shared.scheduleHide(ifAnchoredTo: anchor)
            return
        }

        if hovering {
            let switchedRow = HistoryPopoverManager.shared.prepareForRowHover(anchor)
            hoverCoordinator.setHovered(itemID: item.id)
            if let window = anchor.window, let screen = window.screen {
                windowPosition = window.frame.midX < screen.frame.midX
            }
            schedulePopoverPresentation(anchor: anchor, after: switchedRow ? 0.25 : 0.3)
        } else {
            cancelPopoverTask()
            hoverCoordinator.clearHover(ifMatches: item.id)
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
