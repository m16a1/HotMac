#if DEBUG
import Foundation

/// Synthetic state for rendering the views without an SMC. DEBUG-only, so it
/// is compiled out of the shipped bundle.
extension TemperatureModel {
    /// Replace the published history and snapshot with generated waveforms.
    func loadPreviewData(samples: Int = PreviewData.sampleCount) {
        let now = Date()
        var points: [HistoryPoint] = []
        for index in 0..<samples {
            let time = now.addingTimeInterval(Double(index - samples) * refreshPeriod)
            let phase = Double(index) / Double(samples)
            var values: [String: Double] = [:]
            for wave in PreviewData.waves {
                values[wave.name] = wave.value(inPhase: phase)
            }
            points.append(HistoryPoint(time: time, values: values))
        }
        adopt(
            history: points,
            snapshot: TemperatureSnapshot(
                brand: brand,
                groups: PreviewData.waves.dropLast().map {
                    GroupReading(
                        name: $0.name,
                        average: PreviewData.groupAverage,
                        minimum: PreviewData.groupMinimum,
                        maximum: PreviewData.groupMaximum,
                        count: PreviewData.groupSensorCount
                    )
                },
                hottest: [
                    SensorReading(key: PreviewData.hottestKey, value: PreviewData.hottestValue)
                ],
                highest: PreviewData.hottestValue
            )
        )
    }
}
#endif
