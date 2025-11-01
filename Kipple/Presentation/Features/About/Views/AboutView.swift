//
//  AboutView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/01.
//

import SwiftUI

struct AboutView: View {
    private struct Highlight: Identifiable {
        let id: String
        let icon: String
        let text: LocalizedStringKey
    }

    @ObservedObject private var appSettings = AppSettings.shared

    private let highlights: [Highlight] = [
        .init(id: "local", icon: "lock.shield", text: "All data is stored locally on your Mac"),
        .init(id: "network", icon: "network.slash", text: "No data is sent to external servers"),
        .init(id: "security", icon: "hand.raised", text: "Protected by macOS security features"),
        .init(id: "deletion", icon: "trash", text: "Data can be cleared at any time")
    ]

    var body: some View {
        VStack(spacing: 24) {
            header
            Divider()
            privacySection
            Divider()
            footer
        }
        .padding(24)
        .frame(width: 340)
        .background(Color(NSColor.windowBackgroundColor))
        .environment(\.locale, appSettings.appLocale)
    }

    private var header: some View {
        VStack(spacing: 12) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .cornerRadius(14)
                    .shadow(color: Color.black.opacity(0.08), radius: 6, y: 3)
            }

            Text("Kipple")
                .font(.title2.weight(.semibold))

            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text(versionText(version))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

        }
        .frame(maxWidth: .infinity)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy & Security")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(highlights) { item in
                    Label {
                        Text(item.text)
                            .font(.callout)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: item.icon)
                            .font(.callout.weight(.semibold))
                            .foregroundColor(.accentColor)
                            .frame(width: 20)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let url = URL(string: "https://github.com/nissy/Kipple") {
                Link(destination: url) {
                    Label("View on GitHub", systemImage: "link")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
            }

            Text("© 2025 Kipple")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func versionText(_ version: String) -> String {
        String(
            format: NSLocalizedString("Version %@", comment: "App version label"),
            version
        )
    }
}

#if !CI_BUILD
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
#endif
