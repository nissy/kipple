import SwiftUI

struct DesktopNoteSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
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
        .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding + SettingsLayoutMetrics.groupContentIndent)
        .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
    }
}
