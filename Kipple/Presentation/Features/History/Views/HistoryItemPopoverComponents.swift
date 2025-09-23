//
//  HistoryItemPopoverComponents.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import SwiftUI
import AppKit

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
    
    var pinButtonBackground: Color {
        return item.isPinned ? Color.accentColor : Color.secondary.opacity(0.1)
    }
    
    var pinButtonIcon: String {
        return item.isPinned ? "pin.fill" : "pin"
    }
    
    var pinButtonForeground: Color {
        return item.isPinned ? .white : .secondary
    }
    
    var pinButtonRotation: Double {
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

struct HoverPopoverPresenter<Content: View>: NSViewRepresentable {
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
