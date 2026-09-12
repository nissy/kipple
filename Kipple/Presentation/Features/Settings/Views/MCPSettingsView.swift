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
                SettingsGroup("Add Kipple to an AI client") {
                    copyButton(
                        "Copy Codex add command", format: .codex,
                        successMessage: "Codex add command copied"
                    )
                    copyButton(
                        "Copy Claude Code add command", format: .claudeCode,
                        successMessage: "Claude Code add command copied"
                    )
                    caption("Run the copied command in Terminal. Requires the Codex or Claude Code CLI.")
                    caption("Kipple will be available across all projects.")
                }
                SettingsGroup("Configure with JSON") {
                    copyButton(
                        "Copy MCP settings (JSON)", format: .json,
                        successMessage: "MCP settings (JSON) copied"
                    )
                    caption("Paste this JSON into an AI client's MCP configuration.")
                }
                if !message.isEmpty { caption(LocalizedStringKey(message)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
        }
    }

    private func copyButton(
        _ title: LocalizedStringKey,
        format: MCPIntegration.ConfigurationFormat,
        successMessage: String
    ) -> some View {
        Button {
            guard !busy else { return }
            busy = true
            message = ""
            Task { @MainActor in
                defer { busy = false }
                let success = await integration.copyConfiguration(for: format)
                message = success ? successMessage : "Configuration copy failed; try again"
            }
        } label: {
            Label(title, systemImage: "doc.on.doc")
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!integration.enabled || busy)
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
