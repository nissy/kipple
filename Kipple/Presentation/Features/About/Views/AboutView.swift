//
//  AboutView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/01.
//

import SwiftUI

struct AboutView: View {
    private let privacyItems: [(icon: String, text: String)] = [
        ("lock.shield.fill", "All data is stored locally on your Mac"),
        ("network.slash", "No data is sent to external servers"),
        ("hand.raised.fill", "Protected by macOS security features"),
        ("trash.fill", "Data can be cleared at any time")
    ]
    
    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            VStack(spacing: 12) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
                }
                
                Text("Kipple")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("Version \(version)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Text("Smart Clipboard Manager for macOS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy & Security")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(privacyItems, id: \.text) { item in
                        PrivacyStatement(icon: item.icon, text: item.text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            VStack(spacing: 8) {
                Link(destination: URL(string: "https://github.com/nissy/Kipple")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                        Text("View on GitHub")
                            .font(.system(size: 12, weight: .medium))
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
                
                Text("© 2025 Kipple")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct PrivacyStatement: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 18)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.85))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
    }
}

#if !CI_BUILD
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
#endif
