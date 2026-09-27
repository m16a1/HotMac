import Foundation

// Dependency-free test harness for the HotMac logic layer.
// Run with HotMac/test.py.
//
// These cover the pure logic only (decoding, the key-to-component mapping,
// the plausibility filter, group averaging, the menu bar label). Reading the
// real SMC is verified by running the app, not here.

var checks = 0
var failures = 0

func check(_ label: String, _ condition: Bool) {
    checks += 1
    if condition {
        print("  ok    \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label)")
    }
}

func checkEqual<T: Equatable>(_ label: String, _ got: T, _ want: T) {
    check("\(label)  [got \(got), want \(want)]", got == want)
}

func checkClose(_ label: String, _ got: Double?, _ want: Double, tolerance: Double = 0.0001) {
    guard let got = got else {
        check("\(label)  [got nil, want \(want)]", false)
        return
    }
    check("\(label)  [got \(got), want \(want)]", abs(got - want) <= tolerance)
}

func checkNil(_ label: String, _ got: Double?) {
    check("\(label)  [got \(String(describing: got)), want nil]", got == nil)
}

func checkNilString(_ label: String, _ got: String?) {
    check("\(label)  [got \(String(describing: got)), want nil]", got == nil)
}

// MARK: - byte helpers

func fltLE(_ value: Float) -> [UInt8] {
    withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
}

func fltBE(_ value: Float) -> [UInt8] {
    withUnsafeBytes(of: value.bitPattern.bigEndian) { Array($0) }
}

func int16LE(_ value: Int16) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian) { Array($0) }
}

typealias Table = [String: (format: String, raw: [UInt8], littleEndian: Bool)]

func fltEntry(_ value: Float, _ format: String = "flt ") -> (format: String, raw: [UInt8], littleEndian: Bool) {
    (format, fltLE(value), true)
}

// MARK: - decoding

func testDecoding() {
    print("decoding")
    checkClose("flt little endian", SensorCatalog.decodeValue(format: "flt ", raw: fltLE(42.5), littleEndian: true), 42.5)
    checkClose("flt big endian", SensorCatalog.decodeValue(format: "flt ", raw: fltBE(42.5), littleEndian: false), 42.5)
    checkClose("sp78 signed eighths", SensorCatalog.decodeValue(format: "sp78", raw: int16LE(6528), littleEndian: true), 25.5)
    checkClose("sp78 negative", SensorCatalog.decodeValue(format: "sp78", raw: int16LE(-256), littleEndian: true), -1.0)
    checkClose("ui8", SensorCatalog.decodeValue(format: "ui8", raw: [0x2a], littleEndian: true), 42.0)
    checkClose("i8", SensorCatalog.decodeValue(format: "i8", raw: [0xd6], littleEndian: true), -42.0)
    checkClose("ui16", SensorCatalog.decodeValue(format: "ui16", raw: [0xf4, 0x01], littleEndian: true), 500.0)
    checkClose("ui32", SensorCatalog.decodeValue(format: "ui32", raw: [0x70, 0x11, 0x01, 0x00], littleEndian: true), 70000.0)
    checkClose("format is case and space insensitive", SensorCatalog.decodeValue(format: "FLT ", raw: fltLE(3.5), littleEndian: true), 3.5)
    checkNil("unknown format", SensorCatalog.decodeValue(format: "hex_", raw: [0x01, 0x02], littleEndian: true))
    checkNil("flt with too few bytes", SensorCatalog.decodeValue(format: "flt ", raw: [0x01, 0x02], littleEndian: true))
    checkNil("sp78 with too few bytes", SensorCatalog.decodeValue(format: "sp78", raw: [0x01], littleEndian: true))
}

// MARK: - chip family

func testChipFamily() {
    print("chip family")
    checkEqual("M5 Max", SensorCatalog.chipFamily("Apple M5 Max"), "M5")
    checkEqual("M1", SensorCatalog.chipFamily("Apple M1"), "M1")
    checkEqual("A18 Pro", SensorCatalog.chipFamily("Apple A18 Pro"), "A18")
    checkNilString("unknown brand", SensorCatalog.chipFamily("Intel(R) Core(TM) i7"))
}

// MARK: - aggregate registers

func testAggregateKeys() {
    print("aggregate registers")
    for key in ["Tf05", "Tf06", "Tf15", "Tf16", "Tf45", "Tf46"] {
        check("excluded \(key)", SensorCatalog.aggregateTempKeys.contains(key))
    }
    for key in ["Tp00", "Tp0O", "TCMb", "Tg5q"] {
        check("not excluded \(key)", !SensorCatalog.aggregateTempKeys.contains(key))
    }
}

// MARK: - derived summary keys

func testDerivedKeys() {
    print("derived summaries")
    for key in ["TVMX", "TVmS", "TVms"] {
        check("derived \(key)", SensorCatalog.derivedTempKeys.contains(key))
        check("excluded \(key)", SensorCatalog.excludedTempKeys.contains(key))
    }
    for key in ["Tp00", "TCMb", "TVD0", "TVMR", "Tg5q"] {
        check("not derived \(key)", !SensorCatalog.derivedTempKeys.contains(key))
        check("not excluded \(key)", !SensorCatalog.excludedTempKeys.contains(key))
    }
    checkEqual(
        "excluded set covers both classes",
        SensorCatalog.excludedTempKeys,
        SensorCatalog.aggregateTempKeys.union(SensorCatalog.derivedTempKeys)
    )
}

// MARK: - plausibility filter

func testPlausible() {
    print("plausibility filter")
    let table: Table = [
        "Tp00": fltEntry(45.0),
        "Tp04": fltEntry(0.0),
        "Tf06": fltEntry(88.8125),
        "Tp08": fltEntry(200.0),
        "TVMX": fltEntry(61.0),
    ]
    let found = SensorCatalog.plausible(table, ["Tp00", "Tp04", "Tf06", "Tp08", "Tp0C"])
    checkEqual("keeps only the in-band real sensor", found.map(\.key), ["Tp00"])
    checkEqual("missing key yields nothing", SensorCatalog.plausible(table, ["NOPE"]).count, 0)
    checkEqual("derived summary is filtered", SensorCatalog.plausible(table, ["TVMX"]).count, 0)
}

// MARK: - report snapshot

func testSnapshot() {
    print("report snapshot")
    let table: Table = [
        "Tp00": fltEntry(45.0),
        "Tp04": fltEntry(47.0),
        "Tp0O": fltEntry(43.0),
        "Tg0a": fltEntry(40.0),
        "Tf06": fltEntry(88.8125),
        "TN00": fltEntry(34.0),
        "TVMX": fltEntry(61.0),
        "TVmS": fltEntry(61.0),
        "TVms": fltEntry(61.0),
    ]
    let snap = SensorCatalog.snapshot(brand: "Apple M5 Max", table: table)

    func group(_ name: String) -> GroupReading? {
        snap.groups.first { $0.name == name }
    }

    checkClose("CPU super cores average", group("CPU super cores")?.average, 46.0)
    checkClose("GPU clusters average", group("GPU clusters")?.average, 40.0)
    checkClose("SoC package average", group("SoC package")?.average, 34.0)
    checkEqual("derived summary group is not rendered", group("Virtual memory") == nil, true)
    checkEqual("CPU super cores count", group("CPU super cores")?.count, 2)
    checkEqual("hottest sensor is the real hotspot", snap.hottest.first?.key, "Tp04")
    checkEqual("aggregate slot is not in the hottest list", snap.hottest.contains { $0.key == "Tf06" }, false)
    checkEqual("derived summary is not in the hottest list", snap.hottest.contains { $0.key == "TVMX" }, false)
    checkClose("highest matches the top real sensor", snap.highest, 47.0)
    checkEqual("hottest list is capped", snap.hottest.count <= SensorCatalog.hotspots, true)
}

// MARK: - menu bar label

func testMenuBarLabel() {
    print("menu bar label")
    let model = TemperatureModel(startImmediately: false)
    checkEqual("no reading yet", model.menuBarTitle, "--°")
    model.loadPreviewData()
    checkEqual("preview data shows rounded degrees", model.menuBarTitle, "76°")
}

// MARK: - run

let groups: [(String, () -> Void)] = [
    ("decoding", testDecoding),
    ("chip family", testChipFamily),
    ("aggregate registers", testAggregateKeys),
    ("derived summaries", testDerivedKeys),
    ("plausibility", testPlausible),
    ("snapshot", testSnapshot),
    ("menu bar", testMenuBarLabel),
]

for (_, run) in groups {
    run()
}

print("")
print(failures == 0 ? "\(checks) checks passed" : "\(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
