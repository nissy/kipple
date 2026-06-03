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
        case trimmed
        case formatted
        case formatFailed(String)
        case pinLimitReached
        
        var icon: String {
            switch self {
            case .copied:
                return "checkmark.circle.fill"
            case .trimmed:
                return "scissors"
            case .formatted:
                return "text.alignleft"
            case .formatFailed:
                return "exclamationmark.triangle.fill"
            case .pinLimitReached:
                return "exclamationmark.triangle.fill"
            }
        }
        
        var text: String {
            switch self {
            case .copied:
                return "Copied"
            case .trimmed:
                return NSLocalizedString("editor.trim.success", comment: "Trim success notification")
            case .formatted:
                return NSLocalizedString("editor.format.success", comment: "Format success notification")
            case .formatFailed(let message):
                return message
            case .pinLimitReached:
                return "Pin limit reached"
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .copied, .trimmed:
                return Color(NSColor.controlAccentColor)
            case .formatted:
                return Color.green
            case .formatFailed, .pinLimitReached:
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
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 320, alignment: .leading)
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
