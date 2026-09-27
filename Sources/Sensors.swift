import Foundation

struct SensorReading {
    let key: String
    let value: Double
}

struct GroupReading: Identifiable {
    var id: String { name }
    let name: String
    let average: Double
    let minimum: Double
    let maximum: Double
    let count: Int
}

struct TemperatureSnapshot {
    let brand: String
    let groups: [GroupReading]
    let hottest: [SensorReading]
    let highest: Double?
}

/// Maps SMC temperature keys to named components and builds a report.
///
/// The mapping is derived from the public community key maps (dkorunic/iSMC,
/// exelban/stats, vladkens/macmon). Only the CPU needs a per-chip list because
/// Apple reuses "Tp"/"Te"/"Tf" for different blocks across generations;
/// everything else is prefix-based and stable ("Tg*" is the GPU on every
/// Apple SoC, "Tm*" memory, "TUD*" uncore, "TN*" package).
enum SensorCatalog {
    static let tempMin = 5.0
    static let tempMax = 120.0
    static let hotspots = 5
    static let hottestSeriesName = "Hottest sensor"

    /// The GPU fabric "Min"/"Max" slots (Tf?5/Tf?6) hold each fabric block's
    /// minimum and maximum, not a point reading (iSMC names them "GPU Fabric
    /// Block N Min/Max"). They update rarely: over a 284 s full-load run on the
    /// M5 Max, Tf06 moved once (88.8125 -> 93.3594 °C) while the responsive
    /// sensors around it climbed ~50 °C. A stale per-block extreme would top the
    /// "hottest" list and hide the live hotspot, so these stay out of the
    /// point-sensor ranking (they are still read and shown in the GPU fabric
    /// block when grouped).
    static let aggregateTempKeys: Set<String> = {
        var keys = Set<String>()
        for block in "01234" {
            for slot in "56" {
                keys.insert("Tf\(block)\(slot)")
            }
        }
        return keys
    }()

    /// The "Virtual Memory Summary" keys (iSMC) are derived summaries, not
    /// thermometers. On the M5 Max all three read exactly 61.000000 °C (raw
    /// bytes 00 00 74 42, byte-identical) at idle while the die sits near
    /// 49 °C, and a 60-read burst returns a single distinct bit pattern where
    /// real sensors dither (TCMb: 3 patterns, Tm00: 4). They do follow load
    /// (61 -> 95 °C under a sustained local-LLM run) but are floored at
    /// 61 °C, so at idle they are always the highest reading in the table.
    /// That pegs the menu bar at a constant 61 °C no matter what the machine is
    /// doing, so they are excluded from the group averages and from the
    /// point-sensor ranking. See SENSORS.md.
    static let derivedTempKeys: Set<String> = ["TVMX", "TVmS", "TVms"]

    /// Keys that are read and cached but never ranked or averaged as point
    /// sensors.
    static let excludedTempKeys: Set<String> = aggregateTempKeys.union(derivedTempKeys)

    static let chipCPUGroups: [String: [(String, [String])]] = [
        "M1": [
            ("CPU efficiency cores", ["Tp09", "Tp0T"]),
            ("CPU performance cores", ["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]),
        ],
        "M2": [
            ("CPU efficiency cores", ["Tp1h", "Tp1t", "Tp1p", "Tp1l"]),
            ("CPU performance cores", ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]),
        ],
        "M3": [
            ("CPU efficiency cores", ["Te05", "Te0L", "Te0P", "Te0S"]),
            ("CPU performance cores", ["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]),
        ],
        "M4": [
            ("CPU efficiency cores", ["Te05", "Te0S", "Te09", "Te0H"]),
            ("CPU performance cores", ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]),
        ],
        "M5": [
            ("CPU super cores", ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K"]),
            ("CPU performance cores", ["Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]),
        ],
        "A18": [
            ("CPU efficiency cores", ["Te05", "Te0S"]),
            ("CPU performance cores", ["Tp05", "Tp0D"]),
        ],
    ]

    /// Prefix groups gather every plausible block the chip reports rather than
    /// a hand-picked sample. A M5 Max exposes 84 Tg* GPU clusters; "Tf*" is
    /// omitted on purpose because it is the GPU fabric block, whose Min/Max
    /// aggregate slots would dominate the group and the hotspot scan.
    static let prefixGroups: [(String, String)] = [
        ("GPU clusters", "Tg"),
        ("CPU die", "TCM"),
        ("CPU die aggregate", "TCD"),
        ("Virtual die", "TVD"),
        ("Uncore die", "TUD"),
        ("Memory", "Tm"),
        ("SoC package", "TN"),
    ]

    static let sharedKeys: [(String, [String])] = [
        ("NAND (SSD)", ["TH0x", "TH0a"]),
        ("SSD controller", ["Ts0P", "Ts1P"]),
        ("Battery", ["TB1T", "TB2T"]),
        ("WiFi / Airport", ["TW0P"]),
        ("Airflow", ["TaLP", "TaRF"]),
    ]

    static func chipBrand() -> String {
        sysctlString("machdep.cpu.brand_string") ?? "unknown chip"
    }

    static func chipFamily(_ brand: String) -> String? {
        for family in ["M1", "M2", "M3", "M4", "M5"] {
            if brand.hasPrefix("Apple \(family)") { return family }
        }
        if brand.contains("A18") { return "A18" }
        return nil
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func snapshot(
        brand: String,
        table: [String: (format: String, raw: [UInt8], littleEndian: Bool)]
    ) -> TemperatureSnapshot {
        let family = chipFamily(brand)
        var groups: [(String, [String])] = []
        if let cpu = chipCPUGroups[family ?? ""] {
            groups.append(contentsOf: cpu)
            groups.append(("CPU overall", cpu.flatMap { $0.1 }))
        } else {
            groups.append(("CPU (Tp sensors)", table.keys.filter { $0.hasPrefix("Tp") }.sorted()))
        }
        for (label, prefix) in prefixGroups {
            groups.append((label, table.keys.filter { $0.hasPrefix(prefix) }.sorted()))
        }
        groups.append(contentsOf: sharedKeys)

        var resolved: [GroupReading] = []
        for (label, keys) in groups {
            let readings = plausible(table, keys)
            guard !readings.isEmpty else { continue }
            let values = readings.map(\.value)
            resolved.append(
                GroupReading(
                    name: label,
                    average: values.reduce(0, +) / Double(values.count),
                    minimum: values.min() ?? 0,
                    maximum: values.max() ?? 0,
                    count: values.count
                )
            )
        }

        var hottest: [SensorReading] = []
        for (key, entry) in table {
            guard key.hasPrefix("T"), !excludedTempKeys.contains(key) else { continue }
            guard let value = decodeValue(
                format: entry.format, raw: entry.raw, littleEndian: entry.littleEndian
            ) else { continue }
            guard value >= tempMin, value <= tempMax else { continue }
            hottest.append(SensorReading(key: key, value: value))
        }
        hottest.sort { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }

        return TemperatureSnapshot(
            brand: brand,
            groups: resolved,
            hottest: Array(hottest.prefix(hotspots)),
            highest: hottest.first?.value
        )
    }

    static func plausible(
        _ table: [String: (format: String, raw: [UInt8], littleEndian: Bool)],
        _ keys: [String]
    ) -> [SensorReading] {
        var found: [SensorReading] = []
        for key in keys {
            if excludedTempKeys.contains(key) { continue }
            guard let entry = table[key] else { continue }
            guard let value = decodeValue(
                format: entry.format, raw: entry.raw, littleEndian: entry.littleEndian
            ) else { continue }
            guard value >= tempMin, value <= tempMax else { continue }
            found.append(SensorReading(key: key, value: value))
        }
        return found
    }

    static func decodeValue(format: String, raw: [UInt8], littleEndian: Bool) -> Double? {
        let f = format.trimmingCharacters(in: .whitespaces).lowercased()
        if f.hasPrefix("flt"), raw.count >= 4 {
            return Double(Float(bitPattern: readU32(raw, 0, littleEndian)))
        }
        if f.hasPrefix("sp") || f.hasPrefix("fp") {
            let digits = f.dropFirst(2)
            if !digits.isEmpty, Int(digits) != nil, raw.count >= 2 {
                // Fixed-point formats such as sp78/fp68 encode eighths.
                return Double(Int16(bitPattern: readU16(raw, 0, littleEndian))) / 256.0
            }
        }
        switch f {
        case "i8" where !raw.isEmpty:
            return Double(Int8(bitPattern: raw[0]))
        case "ui8" where !raw.isEmpty:
            return Double(raw[0])
        case "i16" where raw.count >= 2:
            return Double(Int16(bitPattern: readU16(raw, 0, littleEndian)))
        case "ui16" where raw.count >= 2:
            return Double(readU16(raw, 0, littleEndian))
        case "i32" where raw.count >= 4:
            return Double(Int32(bitPattern: readU32(raw, 0, littleEndian)))
        case "ui32" where raw.count >= 4:
            return Double(readU32(raw, 0, littleEndian))
        default:
            return nil
        }
    }

    private static func readU16(_ buffer: [UInt8], _ offset: Int, _ littleEndian: Bool) -> UInt16 {
        if littleEndian {
            return UInt16(buffer[offset]) | (UInt16(buffer[offset + 1]) << 8)
        }
        return (UInt16(buffer[offset]) << 8) | UInt16(buffer[offset + 1])
    }

    private static func readU32(_ buffer: [UInt8], _ offset: Int, _ littleEndian: Bool) -> UInt32 {
        if littleEndian {
            return UInt32(buffer[offset])
                | (UInt32(buffer[offset + 1]) << 8)
                | (UInt32(buffer[offset + 2]) << 16)
                | (UInt32(buffer[offset + 3]) << 24)
        }
        return (UInt32(buffer[offset]) << 24)
            | (UInt32(buffer[offset + 1]) << 16)
            | (UInt32(buffer[offset + 2]) << 8)
            | UInt32(buffer[offset + 3])
    }
}
