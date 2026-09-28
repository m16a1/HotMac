import Testing
@testable import Sensors

/// `SeriesColor`: the palette the charts draw with. What matters is that no two
/// series look alike, and that the spread survives any number of them.
@Suite("Series colors")
struct SeriesColorTests {
    /// Far more series than any chip reports, so a hue that repeats or steps
    /// linearly shows up rather than hiding behind a short run.
    private static let longRun = 60

    /// The most series any chip seen so far reports.
    private static let realisticRun = 15

    @Test func everySeriesGetsItsOwnColor() {
        let colors = (0..<Self.longRun).map(SeriesColor.forIndex)
        #expect(Set(colors).count == colors.count)
    }

    @Test func theHueAdvancesByTheGoldenAngle() {
        for index in 1..<Self.longRun {
            let previous = SeriesColor.forIndex(index - 1).hue
            let current = SeriesColor.forIndex(index).hue
            let advance = (current - previous + 1).truncatingRemainder(dividingBy: 1)
            #expect(abs(advance - SeriesColor.hueStep) < 1e-9)
        }
    }

    @Test func theHuesStayOnTheWheelAndNeverRepeat() {
        let hues = (0..<Self.longRun).map { SeriesColor.forIndex($0).hue }

        #expect(hues.allSatisfy { $0 >= 0 && $0 < 1 })
        #expect(Set(hues).count == hues.count)
    }

    /// Two tones cannot do this: at fifteen series their same-tone hues close to
    /// about 20° apart. Cycling three keeps every same-tone gap above 45°.
    @Test func seriesOfTheSameToneAreFarApartOnTheWheel() {
        let series = (0..<Self.realisticRun).map(SeriesColor.forIndex)

        for brightness in Set(series.map(\.brightness)) {
            let hues = series.filter { $0.brightness == brightness }.map(\.hue).sorted()
            for (left, right) in zip(hues, hues.dropFirst()) {
                #expect(right - left >= 0.125)
            }
        }
    }

    /// The tones must differ in lightness, which is what carries the series
    /// whose hues happen to land close together.
    @Test func theTonesDifferInLightness() {
        let tones = (0..<SeriesColor.tones.count).map(SeriesColor.forIndex)

        #expect(Set(tones.map(\.brightness)).count == tones.count)
        #expect(Set(tones.map(\.saturation)).count > 1)
    }

    /// Every tone has to read on a white window and on a dark one: pale colors
    /// disappear on white, dim ones on black.
    @Test func everyToneStaysVisibleOnEitherBackground() {
        for index in 0..<SeriesColor.tones.count {
            let tone = SeriesColor.forIndex(index)
            #expect(tone.saturation >= 0.5)
            #expect(tone.brightness >= 0.7 && tone.brightness <= 1.0)
        }
    }
}
