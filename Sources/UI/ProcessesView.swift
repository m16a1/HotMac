import SwiftUI
import Sensors

/// The Processes screen: what is loading the machine right now, busiest first,
/// in the shape of `top`.
///
/// The ranking is the model's, computed from two counter samples, so the view
/// only lays the readings out. CPU is a share of one core, so a process using
/// several cores can read above 100%; the GPU share is a share of the whole
/// device. A dash means the figure was not measured — a process owned by another
/// user has no CPU or memory figure of the kernel's own — which is not the same as
/// a measured zero. While this screen is up the model fills those two from `ps`,
/// so the dash shows only when even that has no answer. Every row has a GPU
/// figure: a process with no GPU client at all is using none of the device, so it
/// reads 0.
struct ProcessesView: View {
    @EnvironmentObject var model: TemperatureModel

    private enum Metrics {
        static let pidWidth: CGFloat = 72
        static let cpuWidth: CGFloat = 72
        static let gpuWidth: CGFloat = 72
        static let memoryWidth: CGFloat = 96
    }

    private enum Labels {
        static let process = "Process"
        static let pid = "PID"
        static let cpu = "CPU"
        static let gpu = "GPU"
        static let memory = "Memory"
        static let reading = "Reading processes…"
    }

    var body: some View {
        if model.processes.isEmpty {
            Text(Labels.reading)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(model.processes) {
                processColumn
                pidColumn
                cpuColumn
                gpuColumn
                memoryColumn
            }
            .padding(UI.Layout.panelPadding)
        }
    }

    private var processColumn: TableColumn<ProcessReading, Never, Text, Text> {
        TableColumn(Labels.process) { process in
            Text(process.name)
        }
    }

    private var pidColumn: TableColumn<ProcessReading, Never, Text, Text> {
        TableColumn(Labels.pid) { process in
            Text(String(process.pid))
                .monospacedDigit()
        }
        .width(Metrics.pidWidth)
    }

    private var cpuColumn: TableColumn<ProcessReading, Never, Text, Text> {
        TableColumn(Labels.cpu) { process in
            Text(process.cpuPercent.map { UI.percent($0) } ?? UI.Text.noValue)
                .monospacedDigit()
        }
        .width(Metrics.cpuWidth)
    }

    /// Every process has a GPU figure, so this column is never a dash: a process
    /// with no GPU client at all reads 0, as does one using none of the device.
    private var gpuColumn: TableColumn<ProcessReading, Never, Text, Text> {
        TableColumn(Labels.gpu) { process in
            Text(UI.percent(process.gpuPercent))
                .monospacedDigit()
        }
        .width(Metrics.gpuWidth)
    }

    private var memoryColumn: TableColumn<ProcessReading, Never, Text, Text> {
        TableColumn(Labels.memory) { process in
            Text(process.memoryBytes.map { UI.memory($0) } ?? UI.Text.noValue)
                .monospacedDigit()
        }
        .width(Metrics.memoryWidth)
    }
}
