//
//  AboutView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/01.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header Section
            VStack(spacing: 20) {
                // App Icon
                ZStack {
                    if let appIcon = NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 100, height: 100)
                            .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
                    }
                }
                .padding(.top, 30)
                
                // App Name and Version
                VStack(spacing: 6) {
                    Text("Kipple")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text("Version \(version)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Tagline
                Text("Smart Clipboard Manager for macOS")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
            
            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 40)
            
            // Privacy Section
            VStack(spacing: 20) {
                Text("Privacy & Security")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 30)
                
                VStack(spacing: 0) {
                    PrivacyStatement(
                        icon: "lock.shield.fill",
                        text: "All data is stored locally on your Mac",
                        isFirst: true
                    )
                    
                    PrivacyStatement(
                        icon: "network.slash",
                        text: "No data is sent to external servers",
                        isFirst: false
                    )
                    
                    PrivacyStatement(
                        icon: "hand.raised.fill",
                        text: "Protected by macOS security features",
                        isFirst: false
                    )
                    
                    PrivacyStatement(
                        icon: "trash.fill",
                        text: "Data can be cleared at any time",
                        isFirst: false
                    )
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Footer
            VStack(spacing: 16) {
                Divider()
                    .padding(.horizontal, 40)
                
                VStack(spacing: 8) {
                    Text("© 2025 Kipple")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Link(destination: URL(string: "https://github.com/nishida/Kipple")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 11))
                            Text("View on GitHub")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { inside in
                        if inside {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(width: 400, height: 660)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct PrivacyStatement: View {
    let icon: String
    let text: String
    let isFirst: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.primary.opacity(0.85))
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 1),
                    alignment: isFirst ? .bottom : .top
                )
                .opacity(isFirst ? 0 : 1)
        )
    }
}

#Preview {
    AboutView()
}
