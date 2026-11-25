import SwiftUI

struct DesktopNoteSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        SettingsRow(label: "Default display format") {
            Picker("Default display format", selection: $appSettings.desktopNoteDefaultDisplayMode) {
                Text("Plain Text").tag(AppSettings.DesktopNoteDisplayMode.plainText)
                Text("Markdown").tag(AppSettings.DesktopNoteDisplayMode.markdown)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 205)
        }
        .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding + SettingsLayoutMetrics.groupContentIndent)
        .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
    }
}
