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
        let textKey: String
    }

    @ObservedObject private var appSettings = AppSettings.shared

    private var highlights: [Highlight] {
        [
            .init(id: "local", icon: "lock.shield", textKey: "AboutHighlightLocal"),
            .init(id: "network", icon: "network.slash", textKey: "AboutHighlightNetwork"),
            .init(id: "security", icon: "hand.raised", textKey: "AboutHighlightSecurity"),
            .init(id: "deletion", icon: "trash", textKey: "AboutHighlightDeletion")
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            privacySection
            Divider()
            footer
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .environment(\.locale, appSettings.appLocale)
    }

    private var header: some View {
        VStack(spacing: 8) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.08), radius: 6, y: 3)
            }

            Text(appSettings.localizedString("AboutAppName", comment: "About screen app name"))
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
        VStack(alignment: .leading, spacing: 10) {
            Text(appSettings.localizedString("Privacy & Security", comment: "About screen privacy heading"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(highlights) { item in
                    let text = appSettings.localizedString(
                        item.textKey,
                        comment: "About screen highlight item"
                    )
                    Label {
                        Text(text)
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
                    Label(
                        appSettings.localizedString("View on GitHub", comment: "About screen GitHub link"),
                        systemImage: "link"
                    )
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
            }

            Text(appSettings.localizedString("AboutCopyright", comment: "About screen copyright"))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func versionText(_ version: String) -> String {
        let format = appSettings.localizedString("Version %@", comment: "App version label")
        return String(format: format, locale: appSettings.appLocale, arguments: [version])
    }
}

#if !CI_BUILD
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
#endif
