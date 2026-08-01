//
//  ButtonStyles.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI
import AppKit

enum KippleButtonMetrics {
    static let toolbarSize: CGFloat = 30
    static let compactIconSize: CGFloat = 24
    static let historyRowSize: CGFloat = 22
    static let historyCategoryButtonSize: CGFloat = 24
    static let historyCategoryIconSize: CGFloat = 15
    static let editorControlHeight: CGFloat = 30
    static let editorControlCornerRadius: CGFloat = 8
    static let editorControlHorizontalPadding: CGFloat = 10
    static let editorModeMinWidth: CGFloat = 64
    static let editorTrimButtonWidth: CGFloat = 40
    static let editorFormatMenuButtonWidth: CGFloat = 32
    static let prominentCornerRadius: CGFloat = KippleGlassMetrics.compactInputCornerRadius
    static let prominentFontSize: CGFloat = 12
    static let prominentHorizontalPadding: CGFloat = 14
    static let prominentVerticalPadding: CGFloat = 5
    static let prominentShadowOffsetY: CGFloat = 2
    static let prominentShadowBlurRadius: CGFloat = 4
    static let prominentPressedScale: CGFloat = 0.96
    static let prominentPressedOffsetY: CGFloat = 2
    static let toolbarPressedScale: CGFloat = 0.9
    static let popoverCornerRadius: CGFloat = 4
    static let popoverHorizontalPadding: CGFloat = 12
    static let popoverVerticalPadding: CGFloat = 4
}

enum KippleButtonAppearance {
    static let activeForeground = Color.white
    static let inactiveForeground = Color.secondary
    static let disabledForeground = Color.secondary.opacity(0.62)
    static let disabledOpacity = 0.45
    static let pressedOpacity = 0.78
    static let linkPressedOpacity = 0.6
    static let activeFillInset: CGFloat = 1.5
    static let shadowRadius: CGFloat = 2
    static let shadowY: CGFloat = 2
    static let permissionWarningForeground = Color(.sRGB, red: 0.95, green: 0.12, blue: 0.10)
    static let permissionWarningShadow = Color.black.opacity(0.25)
    static let selectedPillFill = Color.white.opacity(0.2)
    static let inactivePillFill = Color.secondary.opacity(0.1)
    static let selectedSubtleFill = Color.primary.opacity(0.045)
    static let prominentShadowFill = Color.accentColor.opacity(0.3)
    static let prominentGradientEnd = Color.accentColor.opacity(0.8)
    static let destructiveShadowFill = Color.red.opacity(0.3)
    static let destructiveGradientEnd = Color(NSColor.systemRed).opacity(0.8)
    static let popoverPressedFill = Color(NSColor.controlAccentColor).opacity(0.2)
    static let popoverFill = Color(NSColor.controlBackgroundColor)
    static let animation = Animation.spring(response: 0.2, dampingFraction: 0.8)

    static func foreground(isActive: Bool, isEnabled: Bool = true) -> Color {
        guard isEnabled else { return disabledForeground }
        return isActive ? activeForeground : inactiveForeground
    }

    static func circleFill(isActive: Bool, isEnabled: Bool = true) -> LinearGradient {
        if isActive && isEnabled {
            return LinearGradient(
                colors: [
                    Color.accentColor,
                    Color.accentColor.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.secondary.opacity(0.16),
                Color.secondary.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func circleShadow(isActive: Bool, isEnabled: Bool = true) -> Color {
        guard isEnabled else { return Color.clear }
        return isActive ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.04)
    }

    static func compactFill(isActive: Bool) -> Color {
        isActive ? Color.accentColor : inactivePillFill
    }
}

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
                    .fill(Color.primary.opacity(isActive ? 0.035 : 0))
            )
            .overlay(
                shape
                    .stroke(Color.primary.opacity(isActive ? 0.035 : 0), lineWidth: 1)
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
                .glassEffect(kippleGlass(tint: tint, interactive: interactive), in: shape)
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
                .glassEffect(.clear, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.025), lineWidth: 0.5))
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
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.clear.interactive(isEnabled), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(isActive ? 0.03 : 0.02), lineWidth: 0.5))
                .opacity(isEnabled ? 1.0 : 0.42)
        } else {
            let opacity = isActive ? 0.18 : 0.12
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
        } else {
            self
                .background {
                    Rectangle()
                        .fill(.regularMaterial)
                        .ignoresSafeArea()
                }
        }
    }

    @ViewBuilder
    func kippleGlassButton(shape _: ButtonBorderShape = .circle) -> some View {
        self.kippleSystemCircleButton()
    }

    @ViewBuilder
    func kippleSystemCircleButton(
        size: CGFloat = KippleButtonMetrics.toolbarSize,
        isActive: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        self
            .buttonStyle(KippleSystemCircleButtonStyle(size: size, isActive: isActive, isEnabled: isEnabled))
    }

    func kippleSystemCircleSurface(
        size: CGFloat = KippleButtonMetrics.toolbarSize,
        isActive: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        self
            .frame(width: size, height: size)
            .contentShape(Circle())
            .background(
                Circle()
                    .fill(KippleButtonAppearance.circleFill(isActive: isActive, isEnabled: isEnabled))
                    .padding(isActive && isEnabled ? KippleButtonAppearance.activeFillInset : 0)
            )
            .clipShape(Circle())
            .shadow(
                color: KippleButtonAppearance.circleShadow(isActive: isActive, isEnabled: isEnabled),
                radius: KippleButtonAppearance.shadowRadius,
                y: KippleButtonAppearance.shadowY
            )
            .opacity(isEnabled ? 1.0 : KippleButtonAppearance.disabledOpacity)
    }
}

private struct KippleSystemCircleButtonStyle: ButtonStyle {
    let size: CGFloat
    let isActive: Bool
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .kippleSystemCircleSurface(size: size, isActive: isActive, isEnabled: isEnabled)
            .opacity(configuration.isPressed ? KippleButtonAppearance.pressedOpacity : 1.0)
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
            .font(.system(size: KippleButtonMetrics.prominentFontSize, weight: .semibold))
            .padding(.horizontal, KippleButtonMetrics.prominentHorizontalPadding)
            .padding(.vertical, KippleButtonMetrics.prominentVerticalPadding)
            .background(
                ZStack {
                    // Shadow layer
                    RoundedRectangle(cornerRadius: KippleButtonMetrics.prominentCornerRadius, style: .continuous)
                        .fill(KippleButtonAppearance.prominentShadowFill)
                        .offset(y: configuration.isPressed ? 0 : KippleButtonMetrics.prominentShadowOffsetY)
                        .blur(radius: configuration.isPressed ? 0 : KippleButtonMetrics.prominentShadowBlurRadius)
                    
                    // Main button
                    RoundedRectangle(cornerRadius: KippleButtonMetrics.prominentCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor,
                                    KippleButtonAppearance.prominentGradientEnd
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? KippleButtonMetrics.prominentPressedScale : 1.0)
            .offset(y: configuration.isPressed ? KippleButtonMetrics.prominentPressedOffsetY : 0)
            .animation(KippleButtonAppearance.animation, value: configuration.isPressed)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .accentColor : .secondary)
            .scaleEffect(configuration.isPressed ? KippleButtonMetrics.toolbarPressedScale : 1.0)
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.accentColor)
            .opacity(configuration.isPressed ? KippleButtonAppearance.linkPressedOpacity : 1.0)
    }
}

struct PopoverButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.horizontal, KippleButtonMetrics.popoverHorizontalPadding)
            .padding(.vertical, KippleButtonMetrics.popoverVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: KippleButtonMetrics.popoverCornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? 
                          KippleButtonAppearance.popoverPressedFill : 
                          KippleButtonAppearance.popoverFill)
            )
            .foregroundColor(isDestructive ? .red : .primary)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: KippleButtonMetrics.prominentFontSize, weight: .semibold))
            .padding(.horizontal, KippleButtonMetrics.prominentHorizontalPadding)
            .padding(.vertical, KippleButtonMetrics.prominentVerticalPadding)
            .background(
                ZStack {
                    // Shadow layer
                    RoundedRectangle(cornerRadius: KippleButtonMetrics.prominentCornerRadius, style: .continuous)
                        .fill(KippleButtonAppearance.destructiveShadowFill)
                        .offset(y: configuration.isPressed ? 0 : KippleButtonMetrics.prominentShadowOffsetY)
                        .blur(radius: configuration.isPressed ? 0 : KippleButtonMetrics.prominentShadowBlurRadius)
                    
                    // Main button
                    RoundedRectangle(cornerRadius: KippleButtonMetrics.prominentCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(NSColor.systemRed),
                                    KippleButtonAppearance.destructiveGradientEnd
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? KippleButtonMetrics.prominentPressedScale : 1.0)
            .offset(y: configuration.isPressed ? KippleButtonMetrics.prominentPressedOffsetY : 0)
            .animation(KippleButtonAppearance.animation, value: configuration.isPressed)
    }
}
