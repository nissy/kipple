//
//  ResizableSplitView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI

private enum SplitHandleMetrics {
    static let dotSize: CGFloat = 5
    static let dotSpacing: CGFloat = 3
    static let dotCount: Int = 3
    static let activeScale: CGFloat = 1.2
}

struct SplitViewResetConfiguration: Equatable {
    let id: UUID
    let preferredTopHeight: Double?
    let preferredBottomHeight: Double?
}

struct ResizableSplitView<Top: View, Bottom: View>: View {
    let topContent: Top
    let bottomContent: Bottom
    @Binding var topHeight: Double
    let minTopHeight: Double
    let minBottomHeight: Double
    let onHeightsChanged: ((Double, Double) -> Void)?
    let resetConfiguration: SplitViewResetConfiguration?
    let preferredHeightsProvider: (() -> (top: Double?, bottom: Double?))?

    @State private var isDragging = false
    private let handleHeight: Double = 16
    @State private var appliedTopHeight: Double
    @State private var lastGeometryHeight: Double = 0
    @State private var processedResetID: UUID?
    
    init(
        topHeight: Binding<Double>,
        minTopHeight: Double = 100,
        minBottomHeight: Double = 100,
        reset: SplitViewResetConfiguration? = nil,
        preferredHeights: (() -> (top: Double?, bottom: Double?))? = nil,
        onHeightsChanged: ((Double, Double) -> Void)? = nil,
        @ViewBuilder topContent: () -> Top,
        @ViewBuilder bottomContent: () -> Bottom
    ) {
        self._topHeight = topHeight
        self.minTopHeight = minTopHeight
        self.minBottomHeight = minBottomHeight
        self.onHeightsChanged = onHeightsChanged
        self.resetConfiguration = reset
        self.preferredHeightsProvider = preferredHeights
        self.topContent = topContent()
        self.bottomContent = bottomContent()
        _appliedTopHeight = State(initialValue: topHeight.wrappedValue)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // トップコンテンツ
                topContent
                    .frame(height: CGFloat(appliedTopHeight))
                    .clipped()

                // ドラッグハンドル
                ZStack {
                    // Background area
                    Rectangle()
                        .fill(Color(NSColor.windowBackgroundColor))
                        .frame(height: handleHeight)  // 高さを少し増やす
                    
                    // Visual handle - 中央に配置
                    HStack(spacing: SplitHandleMetrics.dotSpacing) {
                        ForEach(0..<SplitHandleMetrics.dotCount) { _ in
                            Circle()
                                .fill(isDragging ? Color.accentColor : Color.gray.opacity(0.4))
                                .frame(
                                    width: SplitHandleMetrics.dotSize,
                                    height: SplitHandleMetrics.dotSize
                                )
                        }
                    }
                    .scaleEffect(isDragging ? SplitHandleMetrics.activeScale : 1.0)
                    .animation(.spring(response: 0.3), value: isDragging)
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let totalHeight = Double(geometry.size.height)
                                let proposed = appliedTopHeight + Double(value.translation.height)
                                let metrics = resolvedHeights(totalHeight: totalHeight, proposedTopHeight: proposed)
                                apply(metrics, updatingBinding: metrics.shouldPersist)
                            }
                            .onEnded { _ in
                                isDragging = false
                                let metrics = resolvedHeights(totalHeight: Double(geometry.size.height))
                                apply(metrics)
                            }
                    )

                // ボトムコンテンツ
                bottomContent
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
            .onAppear {
                let totalHeight = Double(geometry.size.height)
                lastGeometryHeight = totalHeight
                let proposed = preferredProposedTop(totalHeight: totalHeight)
                let metrics = resolvedHeights(totalHeight: totalHeight, proposedTopHeight: proposed)
                apply(metrics)
                applyResetIfNeeded(totalHeight: totalHeight)
            }
            .onChange(of: geometry.size) { newSize in
                let totalHeight = Double(newSize.height)
                lastGeometryHeight = totalHeight
                let proposed = preferredProposedTop(totalHeight: totalHeight)
                let metrics = resolvedHeights(totalHeight: totalHeight, proposedTopHeight: proposed)
                apply(metrics)
                applyResetIfNeeded(totalHeight: totalHeight)
            }
        }
        .onChange(of: topHeight) { newValue in
            appliedTopHeight = newValue
        }
        .onChange(of: resetConfiguration) { _ in
            applyResetIfNeeded(totalHeight: lastGeometryHeight)
        }
    }

    private func resolvedHeights(totalHeight: Double, proposedTopHeight: Double? = nil) -> SplitMetrics {
        guard totalHeight.isFinite, totalHeight > 0 else {
            return SplitMetrics(top: appliedTopHeight, bottom: max(0, -appliedTopHeight), shouldPersist: false)
        }

        let availableHeight = totalHeight - handleHeight
        if availableHeight <= 0 {
            return SplitMetrics(top: appliedTopHeight, bottom: 0, shouldPersist: false)
        }

        let minimumRequired = minTopHeight + minBottomHeight
        if availableHeight < minimumRequired {
            let proposed = proposedTopHeight ?? appliedTopHeight
            let adjustedTop = min(max(proposed, 0), availableHeight)
            let bottom = max(0, availableHeight - adjustedTop)
            return SplitMetrics(top: adjustedTop, bottom: bottom, shouldPersist: false)
        }

        let proposed = proposedTopHeight ?? appliedTopHeight
        let maxAllowedTop = availableHeight - minBottomHeight
        let clampedTop = min(max(proposed, minTopHeight), maxAllowedTop)
        let bottom = availableHeight - clampedTop
        return SplitMetrics(top: clampedTop, bottom: bottom, shouldPersist: true)
    }

    private func apply(_ metrics: SplitMetrics, updatingBinding: Bool = true) {
        appliedTopHeight = metrics.top
        guard metrics.shouldPersist, updatingBinding else { return }
        if topHeight != metrics.top {
            topHeight = metrics.top
        }
        onHeightsChanged?(metrics.top, metrics.bottom)
    }

    private func applyResetIfNeeded(totalHeight: Double) {
        guard let resetConfiguration, totalHeight.isFinite, totalHeight > 0 else { return }
        guard processedResetID != resetConfiguration.id else { return }

        let metrics: SplitMetrics
        if let preferredTop = resetConfiguration.preferredTopHeight {
            metrics = resolvedHeights(totalHeight: totalHeight, proposedTopHeight: preferredTop)
        } else if let preferredBottom = resetConfiguration.preferredBottomHeight {
            let availableHeight = totalHeight - handleHeight
            let proposedTop = availableHeight - preferredBottom
            metrics = resolvedHeights(totalHeight: totalHeight, proposedTopHeight: proposedTop)
        } else {
            return
        }

        guard metrics.shouldPersist else { return }
        apply(metrics)
        processedResetID = resetConfiguration.id
    }

    private func preferredProposedTop(totalHeight: Double) -> Double? {
        guard let provider = preferredHeightsProvider else { return nil }
        let preferences = provider()
        if preferences.top == nil, preferences.bottom == nil {
            return nil
        }
        let availableHeight = totalHeight - handleHeight
        if let top = preferences.top {
            return top
        }
        if let bottom = preferences.bottom {
            return availableHeight - bottom
        }
        return nil
    }
}

private struct SplitMetrics {
    let top: Double
    let bottom: Double
    let shouldPersist: Bool
}
