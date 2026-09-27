import SwiftUI
import Sensors

struct SettingsView: View {
    @EnvironmentObject var model: TemperatureModel

    private enum Metrics {
        static let periodRange: ClosedRange<Double> = 0.5...10
        static let periodStep: Double = 0.5
        static let periodLabelWidth: CGFloat = 56
        static let rowSpacing: CGFloat = 8
    }

    private enum Labels {
        static let refreshSection = "Refresh"
        static let statusSection = "Status"
        static let chip = "Chip"
        static let highest = "Highest"
        static let lastUpdate = "Last update"
        static let error = "Error"
        static let periodFormat = "%.1f s"
        static let timeFormat = "HH:mm:ss"
        static let detectingChip = "detecting…"
        static let periodHint =
            "How often the SMC is sampled. Default is \(TemperatureModel.defaultRefreshPeriod) seconds."
    }

    var body: some View {
        Form {
            Section(Labels.refreshSection) {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    HStack {
                        Slider(
                            value: $model.refreshPeriod,
                            in: Metrics.periodRange,
                            step: Metrics.periodStep
                        )
                        Text(String(format: Labels.periodFormat, model.refreshPeriod))
                            .monospacedDigit()
                            .frame(width: Metrics.periodLabelWidth, alignment: .trailing)
                    }
                    Text(Labels.periodHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(Labels.statusSection) {
                LabeledContent(Labels.chip, value: model.snapshot?.brand ?? Labels.detectingChip)
                LabeledContent(Labels.highest) {
                    Text(UI.temperature(model.snapshot?.highest))
                        .monospacedDigit()
                }
                LabeledContent(Labels.lastUpdate) {
                    Text(model.lastUpdate.map { Self.timeFormatter.string(from: $0) }
                        ?? UI.Text.noValue)
                        .monospacedDigit()
                }
                if let error = model.errorMessage {
                    LabeledContent(Labels.error) {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = Labels.timeFormat
        return formatter
    }()
}
