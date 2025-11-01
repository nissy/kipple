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

            HStack(alignment: .center, spacing: 10) {
                bottomBarActionButton(
                    systemName: "info.circle",
                    help: String(localized: "About"),
                    action: onOpenAbout
                )

                bottomBarActionButton(
                    systemName: "power.circle",
                    help: String(localized: "Quit Kipple"),
                    action: showQuitConfirmationAlert
                )

                bottomBarActionButton(
                    systemName: "gearshape",
                    help: String(localized: "Settings"),
                    action: onOpenSettings
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color(NSColor.windowBackgroundColor).opacity(0.95)
                .background(.ultraThinMaterial)
        )
        .alert("quit.alert.title", isPresented: quitConfirmationBinding) {
            Button("quit.alert.cancel", role: .cancel) {
                cancelQuitConfirmationIfNeeded()
            }
            Button("quit.alert.confirm", role: .destructive) {
                confirmQuitFromDialog()
            }
        } message: {
            Text("quit.alert.message")
        }
    }
}

private extension MainView {
    func bottomBarActionButton(
        systemName: String,
        help: String,
        action: (() -> Void)?
    ) -> some View {
        Button(action: {
            action?()
        }, label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [
                            Color(NSColor.controlBackgroundColor),
                            Color(NSColor.controlBackgroundColor).opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, y: 2)

                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        })
        .buttonStyle(PlainButtonStyle())
        .help(help)
    }
}
