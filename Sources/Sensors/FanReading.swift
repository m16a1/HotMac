import Foundation

/// One cooling fan's speed, as the SMC reports it.
///
/// The SMC numbers fans from zero (`F0`, `F1`, ...) and describes each with a
/// family of keys; only the three speed keys are read. A stopped fan is a
/// legitimate reading of 0 RPM, not a missing one.
public struct FanReading: Identifiable, Equatable, Sendable {
    /// The fan's number in the SMC key table: `0` for `F0Ac`.
    public let index: Int
    /// Current speed in revolutions per minute. Zero when the fan is stopped.
    public let current: Double
    /// The fan's minimum speed, or zero when the machine does not report one.
    public let minimum: Double
    /// The fan's maximum speed, or zero when the machine does not report one.
    public let maximum: Double

    public var id: Int { index }
}

extension SensorCatalog {
    /// The three keys per fan that carry a speed: current, minimum, maximum.
    static let fanSpeedSuffixes: Set<String> = ["Ac", "Mn", "Mx"]

    /// Plausible ceiling for a fan reading, in RPM. A fan that reports more is
    /// a decoding artifact, or a key that is not a speed, and is dropped.
    static let fanRpmMax = 20_000.0

    /// The fan number encoded in a key, `0` for `F0Ac`. Nil when the key is not
    /// a four-character fan key.
    static func fanIndex(of key: String) -> Int? {
        let characters = Array(key)
        guard characters.count == 4, characters[0] == "F",
              let digit = characters[1].wholeNumberValue
        else { return nil }
        return digit
    }

    /// Whether a key is one of the speed keys the model reads.
    ///
    /// The other `F<digit>...` keys (targets, thresholds, status) share the fan
    /// and are skipped, so a tick reads three keys per fan rather than the
    /// whole block.
    static func isFanKey(_ key: String) -> Bool {
        guard fanIndex(of: key) != nil else { return false }
        return fanSpeedSuffixes.contains(String(Array(key)[2...]))
    }

    /// Turn a table of fan keys into one reading per fan, ordered by number.
    ///
    /// A fan needs a current speed to appear; a machine with no `F*` keys
    /// yields an empty list, which is not an error. Minimum and maximum fall
    /// back to zero when the key is absent.
    static func fanReadings(
        from table: [String: (format: String, raw: [UInt8], littleEndian: Bool)]
    ) -> [FanReading] {
        var indices = Set<Int>()
        for key in table.keys {
            if let index = fanIndex(of: key) { indices.insert(index) }
        }

        var readings: [FanReading] = []
        for index in indices.sorted() {
            guard let current = fanSpeed(table, index: index, suffix: "Ac") else { continue }
            readings.append(
                FanReading(
                    index: index,
                    current: current,
                    minimum: fanSpeed(table, index: index, suffix: "Mn") ?? 0,
                    maximum: fanSpeed(table, index: index, suffix: "Mx") ?? 0
                )
            )
        }
        return readings
    }

    /// Decode one fan key, dropping anything outside the plausible band.
    private static func fanSpeed(
        _ table: [String: (format: String, raw: [UInt8], littleEndian: Bool)],
        index: Int,
        suffix: String
    ) -> Double? {
        guard let entry = table["F\(index)\(suffix)"] else { return nil }
        guard let value = decodeValue(
            format: entry.format, raw: entry.raw, littleEndian: entry.littleEndian
        ) else { return nil }
        guard value >= 0, value <= fanRpmMax else { return nil }
        return value
    }
}
