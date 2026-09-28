import SwiftUI
import Sensors

/// The color per chart series, shared by both charts.
///
/// The choice of color lives on `SeriesColor` in the data layer, where it can be
/// tested; this only turns it into a SwiftUI `Color`. Charts' own palette
/// repeats after a handful of series, which draws two components as one line.
enum ChartPalette {
    static func color(at index: Int) -> Color {
        let series = SeriesColor.forIndex(index)
        return Color(
            hue: series.hue,
            saturation: series.saturation,
            brightness: series.brightness
        )
    }

    /// One color per series, in order, so series `n` and `m` never share one.
    static func colors(count: Int) -> [Color] {
        (0..<count).map(color(at:))
    }
}
