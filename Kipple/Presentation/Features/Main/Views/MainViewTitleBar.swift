//
//  MainViewTitleBar.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI
import Combine

final class MainWindowTitleBarState: ObservableObject {
    @Published var isAlwaysOnTop: Bool = false
    @Published var isAlwaysOnTopForcedByQueue: Bool = false
    var toggleHandler: (() -> Void)?
    
    func requestToggle() {
        toggleHandler?()
    }
}

struct MainViewAlwaysOnTopAccessory: View {
    @ObservedObject var state: MainWindowTitleBarState
    let onToggleAlwaysOnTop: () -> Void
    
    var body: some View {
        Button(action: onToggleAlwaysOnTop) {
            ZStack {
                Circle()
                    .fill(state.isAlwaysOnTop ?
                          LinearGradient(
                              colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing
                          ) :
                          LinearGradient(
                              colors: [
                                  Color(NSColor.controlBackgroundColor),
                                  Color(NSColor.controlBackgroundColor).opacity(0.85)
                              ],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing
                          )
                    )
                    .frame(width: 30, height: 30)
                    .shadow(
                        color: state.isAlwaysOnTop ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.1),
                        radius: state.isAlwaysOnTop ? 4 : 2,
                        y: 2
                    )
                
                Image(systemName: state.isAlwaysOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(state.isAlwaysOnTop ? .white : .secondary)
                    .rotationEffect(.degrees(state.isAlwaysOnTop ? 0 : -45))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(state.isAlwaysOnTop ? 1.0 : 0.9)
        .animation(.spring(response: 0.3), value: state.isAlwaysOnTop)
        .help(
            state.isAlwaysOnTopForcedByQueue && !state.isAlwaysOnTop
                ? Text("Queue mode is active but Always on Top is disabled")
                : Text(
                    state.isAlwaysOnTop
                        ? "Disable always on top"
                        : "Enable always on top"
                )
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.clear)
    }
}
