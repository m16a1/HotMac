import Testing
@testable import Sensors

/// `SensorCatalog.decodeValue`: every format the SMC reports, both byte orders,
/// and the ways a value can be unreadable.
@Suite("Decoding")
struct DecodingTests {
    @Test func floatLittleEndian() {
        #expect(SensorCatalog.decodeValue(format: "flt ", raw: Wire.float(42.5), littleEndian: true) == 42.5)
    }

    @Test func floatBigEndian() {
        #expect(
            SensorCatalog.decodeValue(
                format: "flt ", raw: Wire.bigEndianFloat(42.5), littleEndian: false
            ) == 42.5
        )
    }

    @Test(arguments: [(6528, 25.5), (-256, -1.0)])
    func signedEighths(_ raw: Int16, _ want: Double) {
        #expect(SensorCatalog.decodeValue(format: "sp78", raw: Wire.int16(raw), littleEndian: true) == want)
    }

    @Test(arguments: [("ui8", [0x2a], 42.0), ("i8", [0xd6], -42.0)])
    func singleByteIntegers(_ format: String, _ raw: [UInt8], _ want: Double) {
        #expect(SensorCatalog.decodeValue(format: format, raw: raw, littleEndian: true) == want)
    }

    @Test(arguments: [
        ("ui16", [0xf4, 0x01], 500.0),
        ("i16", Wire.int16(-42), -42.0),
        ("ui32", [0x70, 0x11, 0x01, 0x00], 70000.0),
        ("i32", Wire.int32(-70000), -70000.0),
    ])
    func littleEndianIntegers(_ format: String, _ raw: [UInt8], _ want: Double) {
        #expect(SensorCatalog.decodeValue(format: format, raw: raw, littleEndian: true) == want)
    }

    @Test(arguments: [
        ("ui16", [0x01, 0xf4], 500.0),
        ("ui32", [0x00, 0x01, 0x11, 0x70], 70000.0),
        ("i16", [0xff, 0xd6], -42.0),
    ])
    func bigEndianIntegers(_ format: String, _ raw: [UInt8], _ want: Double) {
        #expect(SensorCatalog.decodeValue(format: format, raw: raw, littleEndian: false) == want)
    }

    @Test func formatIsCaseAndSpaceInsensitive() {
        #expect(SensorCatalog.decodeValue(format: "FLT ", raw: Wire.float(3.5), littleEndian: true) == 3.5)
    }

    @Test func unknownFormatDecodesToNothing() {
        #expect(SensorCatalog.decodeValue(format: "hex_", raw: [0x01, 0x02], littleEndian: true) == nil)
    }

    @Test(arguments: [("flt ", [0x01, 0x02]), ("sp78", [0x01])])
    func tooFewBytesDecodesToNothing(_ format: String, _ raw: [UInt8]) {
        #expect(SensorCatalog.decodeValue(format: format, raw: raw, littleEndian: true) == nil)
    }
}
