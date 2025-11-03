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
                        .font(MainViewMetrics.Notification.iconFont)
                    Text(notificationType.text)
                        .font(MainViewMetrics.Notification.textFont)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(notificationType.backgroundColor)
                )
            }
        }
        .padding(.top, 8)
        // 過剰なレイアウト変化を避け、軽量なアニメーションに限定
        .animation(.easeInOut(duration: 0.2), value: showNotification)
    }
}
