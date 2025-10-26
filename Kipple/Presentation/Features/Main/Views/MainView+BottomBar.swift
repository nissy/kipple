//
//  MainView+BottomBar.swift
//  Kipple
//
//  Created by Kipple on 2025/10/20.
//

import SwiftUI
import AppKit

extension MainView {
    var bottomBarContent: some View {
        HStack(alignment: .center, spacing: 12) {
            if let currentContent = viewModel.currentClipboardContent {
                HStack(alignment: .center, spacing: 8) {
                    if AppSettings.shared.enableAutoClear,
                       let remainingTime = viewModel.autoClearRemainingTime {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Text(formatRemainingTime(remainingTime))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Divider()
                            .frame(height: 16)
                            .padding(.horizontal, 4)
                    }

                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(currentContent)
                        .font(.custom(fontManager.historyFont.fontName, size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Button(action: {
                        clearSystemClipboard()
                    }, label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.6))
                            .scaleEffect(hoveredClearButton ? 1.1 : 1.0)
                    })
                    .buttonStyle(PlainButtonStyle())
                    .help("Clear clipboard")
                    .onHover { hovering in
                        hoveredClearButton = hovering
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.1))
                )
            }

            Spacer()

            Button(action: {
                onOpenSettings?()
            }, label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [
                                Color(NSColor.controlBackgroundColor),
                                Color(NSColor.controlBackgroundColor).opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.black.opacity(0.1), radius: 3, y: 2)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            })
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(1.0)
            .help("Settings")

            Button(action: {
                toggleAlwaysOnTop()
            }, label: {
                ZStack {
                    Circle()
                        .fill(isAlwaysOnTop ?
                              activeButtonHighlight :
                              LinearGradient(
                                  colors: [
                                      Color(NSColor.controlBackgroundColor),
                                      Color(NSColor.controlBackgroundColor).opacity(0.8)
                                  ],
                                  startPoint: .topLeading,
                                  endPoint: .bottomTrailing
                              )
                        )
                        .frame(width: 28, height: 28)
                        .shadow(
                            color: isAlwaysOnTop ?
                                Color.accentColor.opacity(0.3) :
                                Color.black.opacity(0.1),
                            radius: 3,
                            y: 2
                        )

                    Image(systemName: isAlwaysOnTop ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isAlwaysOnTop ? .white : .secondary)
                        .rotationEffect(.degrees(isAlwaysOnTop ? 0 : -45))
                }
            })
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isAlwaysOnTop ? 1.0 : 0.9)
            .animation(.spring(response: 0.3), value: isAlwaysOnTop)
            .help(
                isAlwaysOnTopForcedByQueue && !isAlwaysOnTop
                    ? Text("Queue mode is active but Always on Top is disabled")
                    : Text(isAlwaysOnTop ? "Disable always on top" : "Enable always on top")
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color(NSColor.windowBackgroundColor).opacity(0.95)
                .background(.ultraThinMaterial)
        )
    }

    private var activeButtonHighlight: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor,
                Color.accentColor
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
