import SwiftUI
import Charts
import Sensors

struct GraphsView: View {
    @EnvironmentObject var model: TemperatureModel
    @State private var selected: Set<String> = []
    @State private var didInit = false

    private enum Metrics {
        static let sidebarWidth: CGFloat = 210
        static let sidebarSpacing: CGFloat = 6
        static let paneSpacing: CGFloat = 8
        static let readoutFontSize: CGFloat = 28
        static let legendSpacing: CGFloat = 10
        static let axisTickCount = 5
        static let maxInitialSeries = 3
        static let minimumHistoryPoints = 2
    }

    private enum Labels {
        static let seriesHeading = "Series"
        static let clear = "Clear"
        static let collecting = "Collecting data…"
        static let highestCaption = "highest sensor"
        static let timeAxis = "Time"
        static let temperatureAxis = "Temperature"
        static let seriesAxis = "Series"
    }

    /// Series shown when the graph first appears. These are group names chosen
    /// by `SensorCatalog`, so they must match its labels.
    private static let defaultVisible: Set<String> = [
        SensorCatalog.hottestSeriesName,
        SensorCatalog.cpuOverallGroupName,
        "GPU clusters",
        "Memory",
        "SoC package",
    ]

    var body: some View {
        HStack(spacing: 0) {
            seriesList
            Divider()
            chartPane
        }
        .onAppear(perform: initSeries)
        .onChange(of: model.seriesNames) { _, _ in initSeries() }
    }

    private var seriesList: some View {
        VStack(alignment: .leading, spacing: Metrics.sidebarSpacing) {
            Text(Labels.seriesHeading)
                .font(.headline)
            ForEach(model.seriesNames, id: \.self) { name in
                Toggle(name, isOn: binding(for: name))
                    .toggleStyle(.checkbox)
            }
            Spacer(minLength: 0)
        }
        .padding(UI.Layout.panelPadding)
        .frame(width: Metrics.sidebarWidth, alignment: .topLeading)
    }

    private var chartPane: some View {
        VStack(alignment: .leading, spacing: Metrics.paneSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(UI.temperature(model.snapshot?.highest))
                    .font(.system(
                        size: Metrics.readoutFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                Text(Labels.highestCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(Labels.clear, action: model.clearHistory)
                    .controlSize(.small)
                    .disabled(model.history.isEmpty)
            }

            if model.history.count < Metrics.minimumHistoryPoints {
                Text(Labels.collecting)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(model.seriesNames.filter { selected.contains($0) }, id: \.self) { name in
                        ForEach(model.history) { point in
                            if let value = point.values[name] {
                                LineMark(
                                    x: .value(Labels.timeAxis, point.time),
                                    y: .value(Labels.temperatureAxis, value)
                                )
                                .foregroundStyle(by: .value(Labels.seriesAxis, name))
                                .interpolationMethod(.monotone)
                            }
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(UI.Text.temperatureAxisLabel)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: Metrics.axisTickCount)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: Metrics.legendSpacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(UI.Layout.panelPadding)
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(name) },
            set: { isOn in
                if isOn {
                    selected.insert(name)
                } else {
                    selected.remove(name)
                }
            }
        )
    }

    private func initSeries() {
        guard !didInit, !model.seriesNames.isEmpty else { return }
        didInit = true
        let visible = model.seriesNames.filter { Self.defaultVisible.contains($0) }
        selected = visible.isEmpty
            ? Set(model.seriesNames.prefix(Metrics.maxInitialSeries))
            : Set(visible)
    }
}
