//
//  CopiedNotificationView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI

struct CopiedNotificationView: View {
    @Binding var showNotification: Bool
    var notificationType: NotificationType = .copied
    
    enum NotificationType {
        case copied
        case pinLimitReached
        
        var icon: String {
            switch self {
            case .copied:
                return "checkmark.circle.fill"
            case .pinLimitReached:
                return "exclamationmark.triangle.fill"
            }
        }
        
        var text: String {
            switch self {
            case .copied:
                return "Copied"
            case .pinLimitReached:
                return "Pin limit reached"
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .copied:
                return Color(NSColor.controlAccentColor)
            case .pinLimitReached:
                return Color.orange
            }
        }
    }
    
    var body: some View {
        VStack {
            if showNotification {
                HStack(spacing: 4) {
                    Image(systemName: notificationType.icon)
                        .font(.system(size: 11))
                    Text(notificationType.text)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(notificationType.backgroundColor)
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale)
                ))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showNotification)
            }
        }
        .padding(.top, 8)
    }
}
