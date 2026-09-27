import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: TemperatureModel

    var body: some View {
        Form {
            Section("Refresh") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Slider(value: $model.refreshPeriod, in: 0.5...10, step: 0.5)
                        Text(String(format: "%.1f s", model.refreshPeriod))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                    Text("How often the SMC is sampled. Default is 2 seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Status") {
                LabeledContent("Chip", value: model.snapshot?.brand ?? "detecting…")
                LabeledContent("Highest") {
                    Text(model.snapshot?.highest.map { String(format: "%.1f °C", $0) } ?? "—")
                        .monospacedDigit()
                }
                LabeledContent("Last update") {
                    Text(model.lastUpdate.map { Self.timeFormatter.string(from: $0) } ?? "—")
                        .monospacedDigit()
                }
                if let error = model.errorMessage {
                    LabeledContent("Error") {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
