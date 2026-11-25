import SwiftUI

struct DesktopNoteSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(label: "Default display format") {
                Picker("Default display format", selection: $appSettings.desktopNoteDefaultDisplayMode) {
                    Text("Plain Text").tag(AppSettings.DesktopNoteDisplayMode.plainText)
                    Text("Markdown").tag(AppSettings.DesktopNoteDisplayMode.markdown)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 205)
            }
            SettingsRow(label: "Glass transparency") {
                HStack(spacing: 10) {
                    Slider(
                        value: $appSettings.desktopNoteTransparency,
                        in: AppSettings.desktopNoteTransparencyRange,
                        step: 0.05
                    )
                    .accessibilityLabel(Text("Glass transparency"))
                    Text(appSettings.desktopNoteTransparency, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(minWidth: 38, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding + SettingsLayoutMetrics.groupContentIndent)
        .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
    }
}
