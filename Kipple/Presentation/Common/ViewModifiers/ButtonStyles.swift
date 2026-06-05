//
//  ButtonStyles.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI
import AppKit

extension View {
    @ViewBuilder
    func kippleGlassPanel(
        cornerRadius: CGFloat = 20,
        fillOpacity _: Double = 0.26,
        strokeOpacity _: Double = 0,
        highlightOpacity _: Double = 0.08
    ) -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    func kippleSubtleControl<S: Shape>(
        in shape: S,
        isActive: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        self
            .background(
                shape
                    .fill(Color.white.opacity(isActive ? 0.05 : 0))
            )
            .overlay(
                shape
                    .stroke(Color.white.opacity(isActive ? 0.075 : 0), lineWidth: 1)
            )
            .opacity(isEnabled ? 1.0 : 0.38)
    }

    @ViewBuilder
    func kippleLiquidGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        fallbackFill: Color = .clear,
        strokeColor: Color = .clear,
        strokeWidth: CGFloat = 0,
        shadowColor: Color = Color.black.opacity(0.08),
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            self
                .background {
                    shape
                        .fill(Color.clear)
                        .glassEffect(kippleGlass(tint: tint, interactive: interactive), in: shape)
                }
                .overlay(shape.stroke(strokeColor, lineWidth: strokeWidth))
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .background(fallbackFill, in: shape)
                .overlay(shape.stroke(strokeColor, lineWidth: strokeWidth))
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        }
    }

    @ViewBuilder
    func kippleLiquidControlGroup<S: Shape>(in shape: S, isEnabled: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            self
                .opacity(isEnabled ? 1.0 : 0.42)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .opacity(isEnabled ? 1.0 : 0.42)
        }
    }

    @ViewBuilder
    func kippleControlSurface<S: Shape>(
        in shape: S,
        isActive: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        let opacity = isActive ? 0.18 : 0.12
        if #available(macOS 26.0, *) {
            self
                .background(.regularMaterial, in: shape)
                .background(Color.primary.opacity(opacity), in: shape)
                .opacity(isEnabled ? 1.0 : 0.42)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .background(Color.primary.opacity(opacity), in: shape)
                .opacity(isEnabled ? 1.0 : 0.42)
        }
    }

    @ViewBuilder
    func kippleLiquidWindowBackground() -> some View {
        if #available(macOS 26.0, *) {
            self
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.94))
                        .ignoresSafeArea()
                }
        } else {
            self
                .background {
                    Rectangle()
                        .fill(.regularMaterial)
                        .ignoresSafeArea()
                }
        }
    }
}

@available(macOS 26.0, *)
private func kippleGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.clear
    if let tint {
        glass = glass.tint(tint)
    }
    return glass.interactive(interactive)
}

struct ProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    // Shadow layer
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.3))
                        .offset(y: configuration.isPressed ? 0 : 2)
                        .blur(radius: configuration.isPressed ? 0 : 4)
                    
                    // Main button
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor,
                                    Color.accentColor.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .accentColor : .secondary)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.accentColor)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

struct PopoverButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? 
                          Color(NSColor.controlAccentColor).opacity(0.2) : 
                          Color(NSColor.controlBackgroundColor))
            )
            .foregroundColor(isDestructive ? .red : .primary)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    // Shadow layer
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.3))
                        .offset(y: configuration.isPressed ? 0 : 2)
                        .blur(radius: configuration.isPressed ? 0 : 4)
                    
                    // Main button
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(NSColor.systemRed),
                                    Color(NSColor.systemRed).opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
