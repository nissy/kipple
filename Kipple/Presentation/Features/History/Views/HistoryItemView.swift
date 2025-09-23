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
    let historyFont: Font // フォントをパラメータとして受け取る
    
    @State private var isHovered = false
    @State private var isShowingPopover = false
    @State private var popoverTimer: Timer?
    @State private var windowPosition: Bool? // 初期値をnilに設定
    @State private var isScrolling = false
    
    var body: some View {
        ZStack {
            // 背景全体をクリック可能にするための透明レイヤー（パディングを含む全体）
            backgroundView
                .contentShape(Rectangle())
                .onTapGesture {
                    closePopover()
                    onTap()
                }

            HStack(spacing: 8) {
            // ピンボタン
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
            
            // カテゴリアイコン（アクション可能な場合はボタンとして機能）
            if item.isActionable {
                ZStack {
                    Circle()
                        .fill(isSelected ? 
                            Color.white.opacity(0.2) : 
                            Color.accentColor
                        )
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: item.category.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : .white)
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
                .onTapGesture {
                    closePopover()
                    item.performAction()
                }
                .help(item.actionTitle ?? "")
            } else if let onCategoryTap = onCategoryTap {
                ZStack {
                    Circle()
                        .fill(isSelected ? 
                            Color.white.opacity(0.2) : 
                            Color.secondary.opacity(0.1)
                        )
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
                            .fill(isSelected ? 
                                Color.white.opacity(0.2) : 
                                Color.secondary.opacity(0.1)
                            )
                    )
            }
            
            Text(getDisplayContent())
                .font(historyFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    closePopover()
                    onTap()
                }

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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            // スクロール中はポップオーバーを表示しない
            guard !isScrolling else {
                isHovered = hovering
                return
            }
            
            isHovered = hovering
            
            cancelPopoverTimer()
            
            if hovering {
                schedulePopoverPresentation()
            } else {
                closePopover()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.willStartLiveScrollNotification)) { _ in
            isScrolling = true
            closePopover()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didEndLiveScrollNotification)) { _ in
            isScrolling = false
            // スクロール終了後、ホバー中ならポップオーバーを再開
            if isHovered {
                schedulePopoverPresentation()
            }
        }
        .background(
            HoverPopoverPresenter(
                isPresented: $isShowingPopover,
                arrowEdge: popoverArrowEdge
            ) {
                ClipboardItemPopover(item: item)
            }
        )
        .onDisappear {
            closePopover()
        }
    }
    
    private func getDisplayContent() -> String {
        if let newlineIndex = item.content.firstIndex(of: "\n") {
            return String(item.content[..<newlineIndex]) + "…"
        }
        return item.content
    }
    
    private func checkWindowPosition() -> Bool {
        // メインウィンドウを取得（より確実な方法）
        guard let mainWindow = NSApp.windows.first(where: { window in
            window.isVisible && 
            window.level == .normal &&
            window.contentViewController != nil
        }) else {
            // ウィンドウが見つからない場合はデフォルトで左側
            return true
        }
        
        // ウィンドウが表示されている画面を取得
        guard let currentScreen = mainWindow.screen ?? NSScreen.main else {
            return true
        }
        
        let screenFrame = currentScreen.frame
        let windowFrame = mainWindow.frame
        let screenCenter = screenFrame.midX
        
        // ウィンドウの中心がスクリーンの中心より左にあるかどうか
        return windowFrame.midX < screenCenter
    }
    
    private var popoverArrowEdge: Edge {
        // プレビューの矢印の向きを調整（ウィンドウの位置に基づいて左右に表示）
        // 初期値がnilの場合はデフォルトで右側に表示
        return (windowPosition ?? true) ? .trailing : .leading
    }

    private func schedulePopoverPresentation() {
        cancelPopoverTimer()
        
        popoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            if isHovered && !isScrolling {
                if windowPosition == nil {
                    windowPosition = checkWindowPosition()
                }
                isShowingPopover = true
            }
        }
    }

    private func cancelPopoverTimer() {
        popoverTimer?.invalidate()
        popoverTimer = nil
    }

    private func closePopover() {
        cancelPopoverTimer()
        if isShowingPopover {
            isShowingPopover = false
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isSelected ? 
                AnyShapeStyle(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )) :
                AnyShapeStyle(Color(NSColor.quaternaryLabelColor).opacity(isHovered ? 0.5 : 0.2))
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
}

// MARK: - Popover Content
struct ClipboardItemPopover: View {
    let item: ClipItem
    @StateObject private var fontManager = FontManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // カテゴリバッジとアプリ情報
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: item.category.icon)
                        .font(.system(size: 12))
                    Text(item.category.rawValue)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(categoryColor)
                )
                
                Spacer()
                
                // アプリケーション情報
                if item.sourceApp != nil || item.windowTitle != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let appName = item.sourceApp {
                            HStack(spacing: 4) {
                                Image(systemName: "app.badge.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor)
                                Text(appName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        if let windowTitle = item.windowTitle {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(windowTitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            
            // コンテンツを直接表示（シンプル化してパフォーマンス向上）
            Text(String(item.content.prefix(500))) // 最大50０文字に制限
                .font(Font(fontManager.historyFont))
                .lineSpacing(4)
                .lineLimit(10) // 10行に制限
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(16)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(NSColor.textBackgroundColor))
            
            // 詳細情報セクション
            VStack(alignment: .leading, spacing: 12) {
                // 詳細メタデータ
                HStack(spacing: 16) {
                    // 文字数
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Characters")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("\(item.characterCount)")
                            .font(.system(size: 10, weight: .medium))
                    }
                    
                    // 時刻
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copied")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(item.formattedTimestamp)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 320) // サイズを小さく
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 6, y: 3)
    }
    
    // MARK: - Helper Properties
    
    private var categoryColor: Color {
        switch item.category {
        case .all: return .gray
        case .url, .urls: return .blue
        case .email, .emails: return .green
        case .code: return .purple
        case .filePath, .files: return .orange
        case .shortText: return .orange
        case .longText: return .indigo
        case .numbers: return .cyan
        case .json: return .purple
        case .general: return .gray
        case .kipple: return .accentColor
        }
    }
}

// MARK: - HistoryItemView Helper Properties
extension HistoryItemView {
    
    private var actionIcon: String {
        switch item.category {
        case .url:
            return "safari"
        case .email:
            return "envelope"
        default:
            return "arrow.right.circle"
        }
    }
    
    private var pinButtonBackground: Color {
        return item.isPinned ? Color.accentColor : Color.secondary.opacity(0.1)
    }
    
    private var pinButtonIcon: String {
        return item.isPinned ? "pin.fill" : "pin"
    }
    
    private var pinButtonForeground: Color {
        return item.isPinned ? .white : .secondary
    }
    
    private var pinButtonRotation: Double {
        return item.isPinned ? 0 : -45
    }
}

// ClipboardItemPopover Extension
extension ClipboardItemPopover {
    private var actionIcon: String {
        switch item.category {
        case .url:
            return "safari"
        case .email:
            return "envelope"
        default:
            return "arrow.right.circle"
        }
    }
}

// MARK: - NSPopover Bridge

private struct HoverPopoverPresenter<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let arrowEdge: Edge
    let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.coordinator = context.coordinator
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        context.coordinator.anchorView = nsView
        context.coordinator.update(
            isPresented: $isPresented,
            arrowEdge: arrowEdge
        ) { AnyView(content()) }
    }

    final class AnchorView: NSView {
        weak var coordinator: Coordinator?

        override func layout() {
            super.layout()
            coordinator?.anchorViewDidLayout(self)
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if let superview {
                frame = superview.bounds
            }
            coordinator?.anchorViewDidLayout(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.anchorViewDidMoveToWindow(self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var isPresented: Binding<Bool> = .constant(false)
        var arrowEdge: Edge = .trailing
        var contentProvider: (() -> AnyView)?
        weak var anchorView: AnchorView?

        private var popover: NSPopover?
        private var needsPresentation = false

        func update(
            isPresented: Binding<Bool>,
            arrowEdge: Edge,
            content: @escaping () -> AnyView
        ) {
            self.isPresented = isPresented
            self.arrowEdge = arrowEdge
            contentProvider = content
            presentIfPossible()
        }

        func anchorViewDidMoveToWindow(_ anchorView: AnchorView) {
            self.anchorView = anchorView
            if anchorView.window != nil {
                presentIfPossible()
            } else {
                dismissPopover()
            }
        }

        func anchorViewDidLayout(_ anchorView: AnchorView) {
            if let popover, popover.isShown {
                popover.positioningRect = anchorView.bounds
                popover.contentViewController?.view.layoutSubtreeIfNeeded()
            } else if needsPresentation {
                presentIfPossible()
            }
        }

        private func presentIfPossible() {
            guard let anchorView, let contentProvider else { return }

            guard isPresented.wrappedValue else {
                dismissPopover()
                return
            }

            guard anchorView.window != nil else {
                needsPresentation = true
                return
            }

            needsPresentation = false

            if let popover {
                if let hosting = popover.contentViewController as? NSHostingController<AnyView> {
                    hosting.rootView = contentProvider()
                } else {
                    let hosting = NSHostingController(rootView: contentProvider())
                    popover.contentViewController = hosting
                }
                popover.contentViewController?.view.layoutSubtreeIfNeeded()
                popover.contentSize = popover.contentViewController?.view.fittingSize ?? popover.contentSize
                popover.positioningRect = anchorView.bounds
            } else {
                let popover = makePopover()
                let hosting = NSHostingController(rootView: contentProvider())
                popover.contentViewController = hosting
                hosting.view.layoutSubtreeIfNeeded()
                popover.contentSize = hosting.view.fittingSize
                popover.show(
                    relativeTo: anchorView.bounds,
                    of: anchorView,
                    preferredEdge: arrowEdge.nsRectEdge(using: anchorView.userInterfaceLayoutDirection)
                )
                self.popover = popover
            }
        }

        private func makePopover() -> NSPopover {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.delegate = self
            return popover
        }

        private func dismissPopover() {
            popover?.performClose(nil)
            popover = nil
            needsPresentation = false
            if isPresented.wrappedValue {
                isPresented.wrappedValue = false
            }
        }

        func popoverDidClose(_ notification: Notification) {
            popover = nil
            needsPresentation = false
            if isPresented.wrappedValue {
                isPresented.wrappedValue = false
            }
        }
    }
}

private extension Edge {
    func nsRectEdge(using direction: NSUserInterfaceLayoutDirection) -> NSRectEdge {
        switch self {
        case .top:
            return .maxY
        case .bottom:
            return .minY
        case .leading:
            return direction == .rightToLeft ? .maxX : .minX
        case .trailing:
            return direction == .rightToLeft ? .minX : .maxX
        }
    }
}
