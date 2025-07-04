//
//  AboutView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/01.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }
            
            // App Name
            Text("Kipple")
                .font(.title)
                .fontWeight(.semibold)
            
            // Version
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("Version \(version)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            // Description
            Text("A powerful clipboard manager for macOS")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Privacy Notice
            PrivacyNoticeView()
            
            Spacer()
            
            // Copyright and GitHub
            VStack(spacing: 8) {
                Text("© 2025 Kipple")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("Visit on GitHub", destination: URL(string: "https://github.com/nishida/Kipple")!)
                    .font(.caption)
            }
        }
        .padding(30)
        .frame(width: 400, height: 580)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct PrivacyNoticeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy & Security")
                .font(.system(size: 14, weight: .semibold))
            
            VStack(alignment: .leading, spacing: 10) {
                PrivacyItem(
                    icon: "🔒",
                    text: "All clipboard data is stored locally on your device"
                )
                
                PrivacyItem(
                    icon: "🚫",
                    text: "No data is sent to external servers"
                )
                
                PrivacyItem(
                    icon: "🛡️",
                    text: "Your privacy is protected by macOS security"
                )
                
                PrivacyItem(
                    icon: "💾",
                    text: "Data can be cleared at any time from preferences"
                )
                
                PrivacyItem(
                    icon: "🔐",
                    text: "Sensitive data like passwords are not stored"
                )
            }
        }
        .padding(16)
        .background(Color(NSColor.unemphasizedSelectedContentBackgroundColor))
        .cornerRadius(8)
    }
}

struct PrivacyItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(icon)
                .font(.system(size: 16))
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    AboutView()
}
