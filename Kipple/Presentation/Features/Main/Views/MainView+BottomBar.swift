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
            if AppSettings.shared.enableAutoClear,
               let remainingTime = viewModel.autoClearRemainingTime {
                autoClearCountdown(remainingTime)
            }

            Spacer()

            HStack(alignment: .center, spacing: 10) {
                bottomBarActionButton(
                    systemName: "info.circle",
                    helpKey: "About",
                    action: onOpenAbout
                )

                bottomBarActionButton(
                    systemName: "power.circle",
                    helpKey: "Quit Kipple",
                    action: showQuitConfirmationAlert
                )

                bottomBarActionButton(
                    systemName: "gearshape",
                    helpKey: "Settings",
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
    func autoClearCountdown(_ remainingTime: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(formatRemainingTime(remainingTime))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.1))
        )
    }

    func formatRemainingTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60

        if minutes > 0 {
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            return String(format: "00:%02d", seconds)
        }
    }

    func bottomBarActionButton(
        systemName: String,
        helpKey: LocalizedStringKey,
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
                    .frame(
                        width: MainViewMetrics.BottomBar.buttonSize,
                        height: MainViewMetrics.BottomBar.buttonSize
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 2, y: 2)

                Image(systemName: systemName)
                    .font(MainViewMetrics.BottomBar.iconFont)
                    .foregroundColor(.secondary)
            }
        })
        .buttonStyle(PlainButtonStyle())
        .help(Text(helpKey))
    }
}
