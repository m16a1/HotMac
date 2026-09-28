import Foundation

/// The color of one chart series, as hue, saturation and brightness.
///
/// Plain numbers so the palette can be tested without SwiftUI: `ChartPalette`
/// turns these into `Color`. Two things keep the series apart. The hue advances
/// by the golden-angle conjugate, which spreads any number of hues as evenly as
/// possible around the wheel and never repeats one. Three tones cycle, so
/// series that land on nearby hues still differ in lightness, and same-tone
/// series sit about half the wheel apart.
public struct SeriesColor: Hashable, Sendable {
    public let hue: Double
    public let saturation: Double
    public let brightness: Double

    /// Hue advance per series: the golden-angle conjugate, `(sqrt(5) - 1) / 2`.
    static let hueStep = (5.0.squareRoot() - 1.0) / 2.0

    /// Saturation and brightness per tone, cycled in this order. All three are
    /// vivid enough to read on a light or a dark window while still differing
    /// from each other in lightness: light, strong, deep.
    static let tones: [(saturation: Double, brightness: Double)] = [
        (0.8, 1.0),
        (1.0, 0.9),
        (1.0, 0.72),
    ]

    /// The color for the series at `index`, wrapped onto the hue wheel.
    public static func forIndex(_ index: Int) -> SeriesColor {
        let tone = tones[index % tones.count]
        return SeriesColor(
            hue: (Double(index) * hueStep).truncatingRemainder(dividingBy: 1.0),
            saturation: tone.saturation,
            brightness: tone.brightness
        )
    }
}
