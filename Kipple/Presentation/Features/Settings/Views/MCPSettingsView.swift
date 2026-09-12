import SwiftUI

struct MCPSettingsView: View {
    @ObservedObject private var integration: MCPIntegration
    @State private var message = ""
    @State private var busy = false

    init(integration: MCPIntegration = .shared) {
        _integration = ObservedObject(wrappedValue: integration)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                SettingsGroup("AI Integration", includeTopDivider: false) {
                    SettingsRow(label: "Enable MCP", isOn: $integration.enabled)
                    caption("AI can add text and replace the clipboard. Clipboard history cannot be read.")
                    caption("Up to 80,000 characters per item.")
                    caption("Local programs running as your user can add text while MCP is enabled.")
                    if !integration.status.isEmpty { caption(LocalizedStringKey(integration.status)) }
                }
                SettingsGroup("Connection settings") {
                    Button("Copy connection settings") {
                        busy = true
                        Task { @MainActor in
                            defer { busy = false }
                            let success = await integration.copyConfiguration()
                            message = success ? "Connection settings copied" : "Configuration copy failed; try again"
                        }
                    }
                    .disabled(!integration.enabled || busy)
                    caption(
                        "Paste the settings into your AI client. You can use the same settings with multiple clients."
                    )
                }
                if !message.isEmpty { caption(LocalizedStringKey(message)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
        }
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
