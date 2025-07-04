//
//  MainViewTitleBar.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI

struct MainViewTitleBar: View {
    @Binding var isAlwaysOnTop: Bool
    let onToggleAlwaysOnTop: () -> Void
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                // App icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.accentColor, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: "scissors")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Kipple")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Button(action: onToggleAlwaysOnTop) {
                ZStack {
                    Circle()
                        .fill(isAlwaysOnTop ? 
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        .frame(width: 32, height: 32)
                        .shadow(
                            color: isAlwaysOnTop ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.1),
                            radius: isAlwaysOnTop ? 4 : 2,
                            y: 2
                        )
                    
                    Image(systemName: isAlwaysOnTop ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isAlwaysOnTop ? .white : .secondary)
                        .rotationEffect(.degrees(isAlwaysOnTop ? 0 : -45))
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isAlwaysOnTop ? 1.0 : 0.9)
            .animation(.spring(response: 0.3), value: isAlwaysOnTop)
            .help(isAlwaysOnTop ? "Disable always on top" : "Enable always on top")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Blur background
                Color(NSColor.windowBackgroundColor)
                    .opacity(0.8)
                
                // Top highlight
                LinearGradient(
                    colors: [Color.white.opacity(0.1), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .background(.ultraThinMaterial)
        )
    }
}
