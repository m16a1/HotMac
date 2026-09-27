import SwiftUI
import Charts

struct ContentView: View {
    var body: some View {
        TabView {
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
            GraphsView()
                .tabItem { Label("Graphs", systemImage: "chart.xyaxis.line") }
        }
        .frame(minWidth: 700, minHeight: 480)
    }
}

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

struct GraphsView: View {
    @EnvironmentObject var model: TemperatureModel
    @State private var selected: Set<String> = []
    @State private var didInit = false

    private let defaultVisible: Set<String> = [
        SensorCatalog.hottestSeriesName,
        "CPU overall",
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Series")
                .font(.headline)
            ForEach(model.seriesNames, id: \.self) { name in
                Toggle(name, isOn: binding(for: name))
                    .toggleStyle(.checkbox)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 210, alignment: .topLeading)
    }

    private var chartPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.snapshot?.highest.map { String(format: "%.1f °C", $0) } ?? "—")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("highest sensor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear", action: model.clearHistory)
                    .controlSize(.small)
                    .disabled(model.history.isEmpty)
            }

            if model.history.count < 2 {
                Text("Collecting data…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(model.seriesNames.filter { selected.contains($0) }, id: \.self) { name in
                        ForEach(model.history) { point in
                            if let value = point.values[name] {
                                LineMark(
                                    x: .value("Time", point.time),
                                    y: .value("Temperature", value)
                                )
                                .foregroundStyle(by: .value("Series", name))
                                .interpolationMethod(.monotone)
                            }
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("°C")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
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
        let visible = model.seriesNames.filter { defaultVisible.contains($0) }
        selected = visible.isEmpty ? Set(model.seriesNames.prefix(3)) : Set(visible)
    }
}
