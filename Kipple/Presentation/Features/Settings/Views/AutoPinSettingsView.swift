import SwiftUI

struct AutoPinSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        SettingsGroup("Auto Pin") {
            SettingsRow(
                label: "Enable Auto Pin",
                description: "Automatically pin repeated external copies."
            ) {
                Toggle("", isOn: $appSettings.autoPinRepeatedCopyEnabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            SettingsRow(
                label: "Repeated copy window",
                description: "Pin an item when the same text is copied repeatedly within this time."
            ) {
                HStack {
                    TextField(
                        "",
                        value: Binding(
                            get: { Double(appSettings.autoPinRepeatedCopyIntervalSeconds) },
                            set: { appSettings.autoPinRepeatedCopyIntervalSeconds = Int($0) }
                        ),
                        formatter: makeNumberFormatter(minimum: 3, maximum: 10)
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                    Text("seconds")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Stepper(
                        "",
                        value: Binding(
                            get: { Double(appSettings.autoPinRepeatedCopyIntervalSeconds) },
                            set: { appSettings.autoPinRepeatedCopyIntervalSeconds = Int($0) }
                        ),
                        in: 3...10,
                        step: 1
                    )
                    .labelsHidden()
                }
                .disabled(!appSettings.autoPinRepeatedCopyEnabled)
            }

            SettingsRow(
                label: "Repeated copy count",
                description: "History recopy actions are not counted."
            ) {
                HStack {
                    TextField(
                        "",
                        value: Binding(
                            get: { Double(appSettings.autoPinRepeatedCopyCount) },
                            set: { appSettings.autoPinRepeatedCopyCount = Int($0) }
                        ),
                        formatter: makeNumberFormatter(minimum: 3, maximum: 20)
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                    Text("copies")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Stepper(
                        "",
                        value: Binding(
                            get: { Double(appSettings.autoPinRepeatedCopyCount) },
                            set: { appSettings.autoPinRepeatedCopyCount = Int($0) }
                        ),
                        in: 3...20,
                        step: 1
                    )
                    .labelsHidden()
                }
                .disabled(!appSettings.autoPinRepeatedCopyEnabled)
            }
        }
    }

    private func makeNumberFormatter(minimum: Double, maximum: Double) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = NSNumber(value: minimum)
        formatter.maximum = NSNumber(value: maximum)
        formatter.generatesDecimalNumbers = false
        formatter.allowsFloats = false
        return formatter
    }
}
