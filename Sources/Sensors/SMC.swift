import Foundation
import IOKit

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

    private static let structSize = 80
    private static let valueMax = 32

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

    private static let selBegin: UInt32 = 0
    private static let selEnd: UInt32 = 1
    private static let selOperation: UInt32 = 2

    private static let emptyRun = 32

    private var service: io_service_t = 0
    private var connection: io_connect_t = 0

    init() throws {
        guard let matching = IOServiceMatching("AppleSMC") else {
            throw SMCError.serviceNotFound
        }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard svc != 0 else { throw SMCError.serviceNotFound }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(svc, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else {
            IOObjectRelease(svc)
            throw SMCError.openFailed(kr)
        }
        self.service = svc
        self.connection = conn
    }

    deinit {
        close()
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }
    }

    /// Walk the key table and return the size/format/endianness of every key
    /// beginning with "T", which is every temperature sensor.
    ///
    /// The value size is discovered first because the kernel rejects a read
    /// whose declared size does not match the key, and it also requires the
    /// request to be large enough to hold the value.
    func collectTemperatureMeta() throws -> [String: KeyInfo] {
        var meta: [String: KeyInfo] = [:]
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
            guard name.hasPrefix("T") else { continue }
            if let info = try? keyInfo(name) {
                meta[name] = info
            }
        }
        return meta
    }

    func indexKey(_ index: UInt32) throws -> String? {
        let out = try call(op: Self.opKeyFromIndex, index: index)
        guard out.count > Self.resultOff, out[Self.resultOff] == 0 else { return nil }
        let raw = Array(out[0..<4])
        if raw.allSatisfy({ $0 == 0 }) { return nil }
        return Self.decodeFourCC(raw)
    }

    func keyInfo(_ key: String) throws -> KeyInfo {
        let out = try call(op: Self.opKeyInfo, key: key)
        guard out.count > Self.resultOff, out[Self.resultOff] == 0 else {
            throw SMCError.message("key \(key): SMC error")
        }
        let size = Self.readU32(out, Self.sizeOff, true)
        let format = Self.decodeFourCC(Array(out[Self.typeOff..<(Self.typeOff + 4)]))
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
            guard bytes.count == 4 else {
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

        var output = [UInt8](repeating: 0, count: structSize)
        var outSize = structSize

        _ = IOConnectCallMethod(connection, Self.selBegin, nil, 0, nil, 0, nil, nil, nil, nil)
        let kr = input.withUnsafeBytes { inPtr -> kern_return_t in
            output.withUnsafeMutableBytes { outPtr -> kern_return_t in
                IOConnectCallStructMethod(
                    connection,
                    Self.selOperation,
                    inPtr.baseAddress,
                    structSize,
                    outPtr.baseAddress,
                    &outSize
                )
            }
        }
        _ = IOConnectCallMethod(connection, Self.selEnd, nil, 0, nil, 0, nil, nil, nil, nil)

        guard kr == KERN_SUCCESS else { throw SMCError.operationFailed(kr) }
        return Array(output[0..<outSize])
    }

    private static func writeU32(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        buffer[offset] = UInt8(value & 0xff)
        buffer[offset + 1] = UInt8((value >> 8) & 0xff)
        buffer[offset + 2] = UInt8((value >> 16) & 0xff)
        buffer[offset + 3] = UInt8((value >> 24) & 0xff)
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

    private static func decodeFourCC(_ raw: [UInt8]) -> String {
        guard raw.count == 4 else { return "" }
        let reversed = [raw[3], raw[2], raw[1], raw[0]]
        return String(bytes: reversed, encoding: .isoLatin1) ?? ""
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
