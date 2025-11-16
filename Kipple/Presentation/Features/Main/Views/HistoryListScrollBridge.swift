//
//  HistoryListScrollBridge.swift
//  Kipple
//
//  Created by Kipple on 2025/11/16.

import SwiftUI

extension Notification.Name {
    static let historyListShouldScrollToTop = Notification.Name("historyListShouldScrollToTop")
}

struct HistoryListScrollBridge: ViewModifier {
    @State private var scrollToTopTrigger = UUID()

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: scrollToTopTrigger) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("historyListTopAnchor", anchor: .top)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .historyListShouldScrollToTop)) { _ in
                    scrollToTopTrigger = UUID()
                }
        }
    }
}

extension View {
    func historyListScrollBridge() -> some View {
        modifier(HistoryListScrollBridge())
    }
}
