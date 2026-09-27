import Foundation

/// A sensor table as the pure layer sees it: what `SMC` read, keyed by key.
typealias TemperatureTable = [String: (format: String, raw: [UInt8], littleEndian: Bool)]

/// The SMC wire format, as the tests build it.
///
/// The offsets are written out rather than borrowed from `SMC`, on purpose: a
/// fixture that reused the client's own constants could not catch a wrong
/// offset. They are the ones AGENTS.md documents — operation at 42, index at 44,
/// value size at 28, format at 32, attributes at 36, result at 40, value at 48.
enum Wire {
    /// A four-character code as it travels: byte-reversed.
    static func fourcc(_ code: String) -> [UInt8] {
        [UInt8](Array(code.utf8).reversed())
    }

    /// The key a request carries, decoded back out of the wire order.
    static func key(in request: [UInt8]) -> String {
        String(bytes: Array(request[0..<4]).reversed(), encoding: .isoLatin1) ?? ""
    }

    static func float(_ value: Float) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
    }

    static func bigEndianFloat(_ value: Float) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.bigEndian) { Array($0) }
    }

    static func int16(_ value: Int16) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    static func int32(_ value: Int32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    static func uint32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff),
        ]
    }

    static func uint32(at offset: Int, in buffer: [UInt8]) -> UInt32 {
        UInt32(buffer[offset])
            | (UInt32(buffer[offset + 1]) << 8)
            | (UInt32(buffer[offset + 2]) << 16)
            | (UInt32(buffer[offset + 3]) << 24)
    }

    /// A synthetic response struct.
    static func response(
        size: Int = 80,
        result: UInt8 = 0,
        valueSize: UInt32 = 4,
        format: String = "flt ",
        attributes: UInt8 = 0x04,
        value: [UInt8] = [],
        key: String? = nil
    ) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: size)
        if let key { out.replaceSubrange(0..<4, with: fourcc(key)) }
        out.replaceSubrange(28..<32, with: uint32(valueSize))
        out.replaceSubrange(32..<36, with: fourcc(format))
        out[36] = attributes
        out[40] = result
        for (offset, byte) in value.enumerated() where 48 + offset < size {
            out[48 + offset] = byte
        }
        return out
    }
}

/// The usual table entry: a little-endian `flt ` sensor reading.
func floatEntry(_ value: Float) -> (format: String, raw: [UInt8], littleEndian: Bool) {
    ("flt ", Wire.float(value), true)
}
