import Foundation

/// The one kernel interaction the SMC client needs: hand it a request struct
/// and get the response bytes back.
///
/// `IOKitTransport` is the real implementation and the only file that talks to
/// the kernel. This seam exists so the protocol logic below can be exercised
/// without hardware.
protocol SMCTransport: AnyObject {
    /// Send one request and return the response. The kernel requires the
    /// response buffer to be the same length as the request.
    func call(request: [UInt8]) throws -> [UInt8]

    /// Release the underlying connection.
    func close()
}

/// Client for the AppleSMCKeysEndpoint IOKit user client.
///
/// Mirrors the macOS 26 AppleSMC protocol: a single operation selector whose
/// sub-operation is chosen by a byte inside the request struct. Every struct
/// call is bracketed by the no-argument selectors 0 and 1, and four-character
/// codes travel byte-reversed.
final class SMC {
    struct KeyInfo {
        let size: UInt32
        let format: String
        let littleEndian: Bool
    }

    enum SMCError: Error, CustomStringConvertible {
        case serviceNotFound
        case openFailed(kern_return_t)
        case operationFailed(kern_return_t)
        case message(String)

        var description: String {
            switch self {
            case .serviceNotFound:
                return "no AppleSMC service in the IO registry"
            case .openFailed(let kr):
                return "IOServiceOpen failed: \(SMC.kernName(kr))"
            case .operationFailed(let kr):
                return "SMC operation failed: \(SMC.kernName(kr))"
            case .message(let text):
                return text
            }
        }
    }

    /// Every temperature sensor is a key beginning with this character.
    static let temperaturePrefix = "T"

    private static let structSize = 80
    private static let valueMax = 32
    private static let fourccLength = 4

    private static let sizeOff = 28
    private static let typeOff = 32
    private static let attrOff = 36
    private static let resultOff = 40
    private static let data8Off = 42
    private static let indexOff = 44
    private static let bytesOff = 48
    private static let littleEndianBit: UInt8 = 0x04

    private static let opReadBytes: UInt8 = 5
    private static let opKeyFromIndex: UInt8 = 8
    private static let opKeyInfo: UInt8 = 9

    private static let emptyRun = 32

    private let transport: SMCTransport

    init(transport: SMCTransport) {
        self.transport = transport
    }

    deinit {
        close()
    }

    func close() {
        transport.close()
    }

    /// The keys a session keeps metadata for: the temperature sensors and the
    /// fan speed keys.
    struct CollectedMeta {
        let temperatures: [String: KeyInfo]
        let fans: [String: KeyInfo]
    }

    /// Walk the key table once and return the size/format/endianness of every
    /// temperature sensor and every fan speed key.
    ///
    /// The value size is discovered first because the kernel rejects a read
    /// whose declared size does not match the key, and it also requires the
    /// request to be large enough to hold the value. Both families come from
    /// one walk because the walk is the expensive part of connecting.
    func collectMeta() throws -> CollectedMeta {
        var temperatures: [String: KeyInfo] = [:]
        var fans: [String: KeyInfo] = [:]
        var empties = 0
        var index: UInt32 = 0
        while empties < Self.emptyRun {
            let name = try indexKey(index)
            index += 1
            guard let name = name else {
                empties += 1
                continue
            }
            empties = 0
            if name.hasPrefix(Self.temperaturePrefix) {
                if let info = try? keyInfo(name) { temperatures[name] = info }
            } else if SensorCatalog.isFanKey(name) {
                if let info = try? keyInfo(name) { fans[name] = info }
            }
        }
        return CollectedMeta(temperatures: temperatures, fans: fans)
    }

    func indexKey(_ index: UInt32) throws -> String? {
        let out = try call(op: Self.opKeyFromIndex, index: index)
        guard out.count > Self.resultOff, out[Self.resultOff] == 0 else { return nil }
        let raw = Array(out[0..<Self.fourccLength])
        if raw.allSatisfy({ $0 == 0 }) { return nil }
        return Self.decodeFourCC(raw)
    }

    func keyInfo(_ key: String) throws -> KeyInfo {
        let out = try call(op: Self.opKeyInfo, key: key)
        guard out.count > Self.resultOff, out[Self.resultOff] == 0 else {
            throw SMCError.message("key \(key): SMC error")
        }
        let size = Self.readU32(out, Self.sizeOff)
        let format = Self.decodeFourCC(Array(out[Self.typeOff..<(Self.typeOff + Self.fourccLength)]))
        let littleEndian = (out[Self.attrOff] & Self.littleEndianBit) != 0
        return KeyInfo(size: size, format: format, littleEndian: littleEndian)
    }

    /// Read a key's value in a single kernel call.
    func readValue(_ key: String, size: UInt32) throws -> [UInt8] {
        let structSize = size <= UInt32(Self.valueMax) ? Self.structSize : Self.bytesOff + Int(size)
        let out = try call(op: Self.opReadBytes, key: key, dataSize: size, structSize: structSize)
        guard out.count > Self.resultOff, out[Self.resultOff] == 0 else {
            throw SMCError.message("key \(key): SMC error")
        }
        return Array(out[Self.bytesOff..<(Self.bytesOff + Int(size))])
    }

    /// Build the request struct and hand it to the transport.
    private func call(
        op: UInt8,
        key: String? = nil,
        index: UInt32? = nil,
        dataSize: UInt32? = nil,
        structSize: Int = SMC.structSize
    ) throws -> [UInt8] {
        var input = [UInt8](repeating: 0, count: structSize)
        if let key = key {
            let bytes = Array(key.utf8)
            guard bytes.count == Self.fourccLength else {
                throw SMCError.message("key must be exactly 4 characters: \(key)")
            }
            // Four-character codes are stored byte-reversed.
            input[0] = bytes[3]
            input[1] = bytes[2]
            input[2] = bytes[1]
            input[3] = bytes[0]
        }
        if let index = index { Self.writeU32(&input, Self.indexOff, index) }
        if let dataSize = dataSize { Self.writeU32(&input, Self.sizeOff, dataSize) }
        input[Self.data8Off] = op

        return try transport.call(request: input)
    }

    private static func writeU32(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        buffer[offset] = UInt8(value & 0xff)
        buffer[offset + 1] = UInt8((value >> 8) & 0xff)
        buffer[offset + 2] = UInt8((value >> 16) & 0xff)
        buffer[offset + 3] = UInt8((value >> 24) & 0xff)
    }

    /// The struct's size field is a host-order u32. Every Apple SoC is
    /// little-endian, and the per-key attribute byte governs only the *value*
    /// byte order, never the struct fields.
    private static func readU32(_ buffer: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(buffer[offset])
            | (UInt32(buffer[offset + 1]) << 8)
            | (UInt32(buffer[offset + 2]) << 16)
            | (UInt32(buffer[offset + 3]) << 24)
    }

    /// Internal rather than private so the malformed-input branch can be
    /// tested; a four-character code must survive a round trip through a
    /// byte-reversed wire format.
    ///
    /// Built from Unicode scalars because Latin-1 maps byte-for-byte onto
    /// U+0000...U+00FF, which is what the C side sees.
    static func decodeFourCC(_ raw: [UInt8]) -> String {
        guard raw.count == SMC.fourccLength else { return "" }
        return String(raw.reversed().map { Character(UnicodeScalar($0)) })
    }

    private static func kernName(_ kr: kern_return_t) -> String {
        let names: [Int32: String] = [
            0: "success",
            5: "invalid argument",
            0x101: "failure",
            0x102: "aborted",
            0x103: "invalid process",
            0x104: "invalid capability",
            0x105: "invalid rights",
            0x107: "invalid name",
            0x108: "terminated",
            0x109: "invalid state",
            0x10d: "invalid address",
            0x10f: "invalid value",
            0x111: "invalid capture",
            0x118: "bad size",
            0x120: "not supported",
            0x2c2: "bad argument",
            0x2c7: "unsupported",
            0x2c9: "no connection",
            0x2cf: "not permitted",
        ]
        return names[kr] ?? "0x\(String(kr, radix: 16))"
    }
}
