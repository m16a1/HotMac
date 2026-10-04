import SwiftUI
import Sensors

struct SettingsView: View {
    @EnvironmentObject var model: TemperatureModel

    private enum Metrics {
        static let periodRange: ClosedRange<Double> = 0.5...10
        static let periodStep: Double = 0.5
        static let periodLabelWidth: CGFloat = 56
        static let historyRange: ClosedRange<Double> = 60...7200
        static let historyStep: Double = 60
        static let historyLabelWidth: CGFloat = 88
        static let rowSpacing: CGFloat = 8
    }

    private enum Labels {
        static let refreshSection = "Refresh"
        static let historySection = "History"
        static let statusSection = "Status"
        static let chip = "Chip"
        static let highest = "Highest"
        static let lastUpdate = "Last update"
        static let throttling = "Throttling"
        static let gpu = "GPU"
        static let throttleNominal = "Nominal"
        static let throttleFair = "Fair"
        static let throttleSerious = "Serious"
        static let throttleCritical = "Critical"
        static let error = "Error"
        static let periodFormat = "%.1f s"
        static let historyFormat = "%d samples"
        static let timeFormat = "HH:mm:ss"
        static let detectingChip = "detecting…"
        static let periodHint =
            "How often the SMC is sampled. Default is \(TemperatureModel.defaultRefreshPeriod) seconds."
        static let historyHint =
            "How many samples the graph keeps. Default is \(TemperatureModel.defaultHistoryLimit)."
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

            Section(Labels.historySection) {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    HStack {
                        Slider(
                            value: historyBinding,
                            in: Metrics.historyRange,
                            step: Metrics.historyStep
                        )
                        Text(String(format: Labels.historyFormat, model.historyLimit))
                            .monospacedDigit()
                            .frame(width: Metrics.historyLabelWidth, alignment: .trailing)
                    }
                    Text(Labels.historyHint)
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
                LabeledContent(Labels.throttling) {
                    Text(Self.throttlingText(model.throttleState))
                        .foregroundStyle(Self.throttlingColor(model.throttleState))
                }
                LabeledContent(Labels.gpu) {
                    Text(model.gpuUtilization.map { UI.percent($0.percent) } ?? UI.Text.noValue)
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

    /// The OS throttling level, or the placeholder before the first reading.
    private static func throttlingText(_ state: ThrottleState?) -> String {
        guard let state else { return UI.Text.noValue }
        return switch state {
        case .nominal: Labels.throttleNominal
        case .fair: Labels.throttleFair
        case .serious: Labels.throttleSerious
        case .critical: Labels.throttleCritical
        }
    }

    /// Only the levels that mean real throttling get a color.
    private static func throttlingColor(_ state: ThrottleState?) -> Color {
        guard let state else { return .primary }
        return switch state {
        case .nominal, .fair: .primary
        case .serious: .orange
        case .critical: .red
        }
    }

    /// The slider works in `Double`, the model stores a whole sample count.
    private var historyBinding: Binding<Double> {
        Binding(
            get: { Double(model.historyLimit) },
            set: { model.historyLimit = Int($0.rounded()) }
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = Labels.timeFormat
        return formatter
    }()
}
