//
//  CopiedNotificationView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI

struct CopiedNotificationView: View {
    @Binding var showNotification: Bool
    
    var body: some View {
        VStack {
            if showNotification {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text("Copied")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(NSColor.controlAccentColor))
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
