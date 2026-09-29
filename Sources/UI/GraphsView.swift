import SwiftUI
import Charts
import Sensors

struct GraphsView: View {
    @EnvironmentObject var model: TemperatureModel

    private enum Metrics {
        static let sidebarWidth: CGFloat = 210
        static let sidebarSpacing: CGFloat = 6
        static let sectionSpacing: CGFloat = 12
        static let paneSpacing: CGFloat = 8
        static let readoutFontSize: CGFloat = 28
        static let legendSpacing: CGFloat = 10
        static let axisTickCount = 5
        static let minimumHistoryPoints = 2
    }

    private enum Labels {
        static let seriesHeading = "Series"
        static let physicalHeading = "Physical"
        static let physicalHint =
            "Thermometers on the hardware. These are the chips measuring their own heat."
        static let virtualHeading = "Virtual"
        static let virtualHint =
            "Readings Apple computes from the sensors above, not thermometers of their own."
        static let clear = "Clear"
        static let collecting = "Collecting data…"
        static let highestCaption = "highest sensor"
        static let timeAxis = "Time"
        static let temperatureAxis = "Temperature"
        static let seriesAxis = "Series"
    }

    /// The chosen series this chip actually reports, so a selection stored for
    /// a different chip cannot leave the chart blank.
    private var visibleSeries: [String] {
        model.seriesNames.filter { model.selectedSeries.contains($0) }
    }

    /// The series this chip reports, split by kind: the thermometers on the
    /// hardware first, then the readings Apple derives from them. The chart
    /// draws both kinds; only the list separates them, so a computed reading is
    /// never mistaken for a measurement.
    private var physicalSeries: [String] {
        model.seriesNames.filter { !SensorCatalog.isVirtualGroup($0) }
    }

    private var virtualSeries: [String] {
        model.seriesNames.filter(SensorCatalog.isVirtualGroup)
    }

    var body: some View {
        HStack(spacing: 0) {
            seriesList
            Divider()
            chartPane
        }
    }

    private var seriesList: some View {
        VStack(alignment: .leading, spacing: Metrics.sidebarSpacing) {
            Text(Labels.seriesHeading)
                .font(.headline)
            section(Labels.physicalHeading, hint: Labels.physicalHint, names: physicalSeries)
            if !virtualSeries.isEmpty {
                section(Labels.virtualHeading, hint: Labels.virtualHint, names: virtualSeries)
                    .padding(.top, Metrics.sectionSpacing)
            }
            Spacer(minLength: 0)
        }
        .padding(UI.Layout.panelPadding)
        .frame(width: Metrics.sidebarWidth, alignment: .topLeading)
    }

    /// One kind of series: a caption saying what the kind is, then its toggles.
    private func section(_ heading: String, hint: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sidebarSpacing) {
            Text(heading)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(hint)
            ForEach(names, id: \.self) { name in
                Toggle(name, isOn: binding(for: name))
                    .toggleStyle(.checkbox)
                    .help(SensorCatalog.description(for: name))
            }
        }
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
                    ForEach(visibleSeries, id: \.self) { name in
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
                .chartForegroundStyleScale(
                    domain: model.seriesNames,
                    range: ChartPalette.colors(count: model.seriesNames.count)
                )
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
            get: { model.selectedSeries.contains(name) },
            set: { isOn in
                if isOn {
                    model.selectedSeries.insert(name)
                } else {
                    model.selectedSeries.remove(name)
                }
            }
        )
    }
}
