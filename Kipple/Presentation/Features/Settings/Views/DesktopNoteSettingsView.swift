import AppKit
import SwiftUI

struct DesktopNoteSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var displays = DesktopNoteDisplay.connected

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.rowVerticalSpacing) {
            SettingsRow(label: "Default display format") {
                Picker("Default display format", selection: $appSettings.desktopNoteDefaultDisplayMode) {
                    Text("Plain Text").tag(AppSettings.DesktopNoteDisplayMode.plainText)
                    Text("Markdown").tag(AppSettings.DesktopNoteDisplayMode.markdown)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 205)
            }
            SettingsRow(label: "Note creation display") {
                Picker("Note creation display", selection: $appSettings.desktopNoteDisplayID) {
                    Text("Automatic display").tag("")
                    ForEach(displays) { display in
                        Text(verbatim: displayName(for: display)).tag(display.id)
                    }
                    if !appSettings.desktopNoteDisplayID.isEmpty,
                       !displays.contains(where: { $0.id == appSettings.desktopNoteDisplayID }) {
                        Text("Selected display (disconnected)").tag(appSettings.desktopNoteDisplayID)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 205, alignment: .leading)
            }
            SettingsRow(
                label: "Create a note on repeated copy",
                description: "Copy the same text three times within five seconds in another app.",
                isOn: $appSettings.desktopNoteOnRepeatedCopy
            )
        }
        .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding + SettingsLayoutMetrics.groupContentIndent)
        .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
        .onAppear { displays = DesktopNoteDisplay.connected }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = DesktopNoteDisplay.connected
        }
    }

    private func displayName(for display: DesktopNoteDisplay) -> String {
        let name = display.screen.localizedName
        let matching = displays.filter { $0.screen.localizedName == name }
        guard matching.count > 1, let index = matching.firstIndex(where: { $0.id == display.id }) else { return name }
        return "\(name) (\(index + 1))"
    }
}
