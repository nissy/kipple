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
    @Published var isEditorEnabled: Bool = true
    @Published var showsCaptureButton: Bool = false
    @Published var isCaptureEnabled: Bool = false
    @Published var showsQueueButton: Bool = false
    @Published var isQueueEnabled: Bool = false
    @Published var isQueueActive: Bool = false
    @Published var showsQueueLoopButton: Bool = false
    @Published var isQueueLoopEnabled: Bool = false
    @Published var isQueueLoopActive: Bool = false
    
    var toggleAlwaysOnTopHandler: (() -> Void)?
    var toggleEditorHandler: (() -> Void)?
    var startCaptureHandler: (() -> Void)?
    var toggleQueueHandler: (() -> Void)?
    var toggleQueueLoopHandler: (() -> Void)?
    
    func requestToggleAlwaysOnTop() {
        toggleAlwaysOnTopHandler?()
    }
    
    func requestToggleEditor() {
        toggleEditorHandler?()
    }
    
    func requestStartCapture() {
        startCaptureHandler?()
    }
    
    func requestToggleQueue() {
        toggleQueueHandler?()
    }
    
    func requestToggleQueueLoop() {
        toggleQueueLoopHandler?()
    }
}

struct MainViewTitleBarAccessory: View {
    @ObservedObject var state: MainWindowTitleBarState
    
    var body: some View {
        HStack(spacing: 8) {
            if state.showsCaptureButton {
                captureButton
            }
            if state.showsQueueButton {
                queueButton
            }
            if state.showsQueueLoopButton {
                queueLoopButton
            }
            editorButton
            pinButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.clear)
    }
}

private extension MainViewTitleBarAccessory {
    var captureButton: some View {
        Button(action: state.requestStartCapture) {
            ZStack {
                Circle()
                    .fill(state.isCaptureEnabled ? activeGradient : inactiveGradient)
                    .frame(width: 30, height: 30)
                    .shadow(
                        color: state.isCaptureEnabled ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.08),
                        radius: state.isCaptureEnabled ? 4 : 2,
                        y: 2
                    )
                
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(state.isCaptureEnabled ? .white : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(state.isCaptureEnabled ? 1.0 : 0.9)
        .animation(.spring(response: 0.3), value: state.isCaptureEnabled)
        .disabled(!state.isCaptureEnabled)
        .help(Text("Screen Text Capture"))
    }
    
    var queueButton: some View {
        Button(action: state.requestToggleQueue) {
            ZStack {
                Circle()
                    .fill(state.isQueueActive ? activeGradient : inactiveGradient)
                    .frame(width: 30, height: 30)
                    .shadow(
                        color: state.isQueueActive ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.08),
                        radius: state.isQueueActive ? 4 : 2,
                        y: 2
                    )
                
                Image(systemName: "list.number")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(state.isQueueActive ? .white : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(state.isQueueActive ? 1.0 : 0.9)
        .animation(.spring(response: 0.3), value: state.isQueueActive)
        .disabled(!state.isQueueEnabled)
        .help(Text("Queue"))
    }
    
    var queueLoopButton: some View {
        Button(action: state.requestToggleQueueLoop) {
            ZStack {
                Circle()
                    .fill(state.isQueueLoopActive ? activeGradient : inactiveGradient)
                    .frame(width: 30, height: 30)
                    .shadow(
                        color: state.isQueueLoopActive ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.08),
                        radius: state.isQueueLoopActive ? 4 : 2,
                        y: 2
                    )
                
                Image(systemName: state.isQueueLoopActive ? "repeat.circle.fill" : "repeat")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(state.isQueueLoopActive ? .white : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(state.isQueueLoopActive ? 1.0 : 0.9)
        .animation(.spring(response: 0.3), value: state.isQueueLoopActive)
        .disabled(!state.isQueueLoopEnabled)
        .help(Text("Loop"))
    }
    
    var editorButton: some View {
        Button(action: state.requestToggleEditor) {
            ZStack {
                Circle()
                    .fill(editorButtonBackground)
                    .frame(width: 30, height: 30)
                    .shadow(
                        color: state.isEditorEnabled ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.08),
                        radius: state.isEditorEnabled ? 4 : 2,
                        y: 2
                    )
                
                Image(systemName: state.isEditorEnabled ? "square.and.pencil" : "square.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(state.isEditorEnabled ? .white : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(state.isEditorEnabled ? 1.0 : 0.92)
        .animation(.spring(response: 0.3), value: state.isEditorEnabled)
        .help(state.isEditorEnabled ? Text("Hide editor panel") : Text("Show editor panel"))
    }
    
    var pinButton: some View {
        Button(action: state.requestToggleAlwaysOnTop) {
            ZStack {
                Circle()
                    .fill(pinButtonBackground)
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
    }
    
    var editorButtonBackground: LinearGradient {
        state.isEditorEnabled ? activeGradient : inactiveGradient
    }
    
    var pinButtonBackground: LinearGradient {
        state.isAlwaysOnTop ? activeGradient : inactiveGradient
    }
    
    var activeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var inactiveGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(NSColor.controlBackgroundColor),
                Color(NSColor.controlBackgroundColor).opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
