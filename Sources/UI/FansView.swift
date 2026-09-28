import SwiftUI
import Charts
import Sensors

struct FansView: View {
    @EnvironmentObject var model: TemperatureModel

    private enum Metrics {
        static let readoutFontSize: CGFloat = 28
        static let readoutSpacing: CGFloat = 28
        static let paneSpacing: CGFloat = 12
        static let legendSpacing: CGFloat = 10
        static let axisTickCount = 5
        static let minimumPoints = 2
    }

    private enum Labels {
        static let clear = "Clear"
        static let collecting = "Collecting data…"
        static let empty = "This machine reports no fans."
        static let timeAxis = "Time"
        static let seriesAxis = "Fan"
        static let fanPrefix = "Fan"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.paneSpacing) {
            header
            if model.fans.isEmpty {
                Text(Labels.empty)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if model.fanHistory.count < Metrics.minimumPoints {
                Text(Labels.collecting)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
            }
        }
        .padding(UI.Layout.panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.readoutSpacing) {
            ForEach(model.fans) { fan in
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.caption(fan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UI.rpm(fan.current))
                        .font(.system(
                            size: Metrics.readoutFontSize,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .monospacedDigit()
                }
            }
            Spacer()
            Button(Labels.clear, action: model.clearHistory)
                .controlSize(.small)
                .disabled(model.fanHistory.isEmpty)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(model.fans) { fan in
                ForEach(model.fanHistory) { point in
                    if let speed = point.speeds[fan.index] {
                        LineMark(
                            x: .value(Labels.timeAxis, point.time),
                            y: .value(UI.Text.rpmAxisLabel, speed)
                        )
                        .foregroundStyle(by: .value(Labels.seriesAxis, Self.name(fan)))
                        .interpolationMethod(.monotone)
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartForegroundStyleScale(
            domain: model.fans.map(Self.name),
            range: ChartPalette.colors(count: model.fans.count)
        )
        .chartYAxisLabel(UI.Text.rpmAxisLabel)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: Metrics.axisTickCount)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: Metrics.legendSpacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The SMC exposes a fan number, not a name, so the fan is labelled by
    /// position. The range is only shown when the machine reports one.
    private static func name(_ fan: FanReading) -> String {
        "\(Labels.fanPrefix) \(fan.index + 1)"
    }

    private static func caption(_ fan: FanReading) -> String {
        guard fan.maximum > 0 else { return name(fan) }
        return "\(name(fan)) · \(UI.rpmRange(fan.minimum, fan.maximum))"
    }
}
