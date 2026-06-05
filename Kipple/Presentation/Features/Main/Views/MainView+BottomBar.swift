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
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .kippleLiquidControlGroup(in: Capsule(), isEnabled: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        helpKey: LocalizedStringKey,
        action: (() -> Void)?
    ) -> some View {
        Button(action: {
            action?()
        }, label: {
            Image(systemName: systemName)
                .font(MainViewMetrics.BottomBar.iconFont)
                .foregroundColor(.secondary)
                .frame(
                    width: MainViewMetrics.BottomBar.buttonSize,
                    height: MainViewMetrics.BottomBar.buttonSize
                )
                .kippleControlSurface(in: Circle(), isEnabled: true)
        })
        .buttonStyle(PlainButtonStyle())
        .help(Text(helpKey))
    }
}
