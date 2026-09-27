@testable import Sensors

/// Emulates the kernel side of the SMC user client: an ordered key table, key
/// info, and value reads, driven by the operation byte in the request.
///
/// The request offsets are the ones AGENTS.md documents. They are repeated here
/// rather than borrowed from `SMC`, so a wrong offset in the client cannot go
/// unnoticed.
final class FakeSMCTransport: SMCTransport {
    let order: [String]
    let table: TemperatureTable
    /// Keys whose key-info call fails as if the kernel refused it.
    let missingInfoKeys: Set<String>
    /// Keys whose value read fails as if the kernel refused it.
    let unreadableKeys: Set<String>

    private(set) var requests: [[UInt8]] = []
    private(set) var closeCount = 0

    init(
        order: [String],
        table: TemperatureTable,
        missingInfoKeys: Set<String> = [],
        unreadableKeys: Set<String> = []
    ) {
        self.order = order
        self.table = table
        self.missingInfoKeys = missingInfoKeys
        self.unreadableKeys = unreadableKeys
    }

    func call(request: [UInt8]) throws -> [UInt8] {
        requests.append(request)
        let size = request.count
        switch request[42] {
        case 8:
            let index = Int(Wire.uint32(at: 44, in: request))
            guard index < order.count else { return [UInt8](repeating: 0, count: size) }
            let key = order[index]
            return Wire.response(
                size: size,
                valueSize: UInt32(table[key]?.raw.count ?? 4),
                key: key
            )
        case 9, 5:
            let key = Wire.key(in: request)
            guard let entry = table[key] else { return Wire.response(size: size, result: 0x85) }
            if request[42] == 9 {
                if missingInfoKeys.contains(key) { return Wire.response(size: size, result: 0x85) }
                return Wire.response(
                    size: size,
                    valueSize: UInt32(entry.raw.count),
                    format: entry.format,
                    attributes: entry.littleEndian ? 0x04 : 0,
                    key: key
                )
            }
            if unreadableKeys.contains(key) { return Wire.response(size: size, result: 0x85) }
            return Wire.response(
                size: size,
                valueSize: UInt32(entry.raw.count),
                format: entry.format,
                attributes: entry.littleEndian ? 0x04 : 0,
                value: entry.raw,
                key: key
            )
        default:
            return [UInt8](repeating: 0, count: size)
        }
    }

    func close() {
        closeCount += 1
    }
}

/// Returns a response too short to carry a result byte.
final class TruncatedTransport: SMCTransport {
    func call(request: [UInt8]) throws -> [UInt8] {
        [UInt8](repeating: 0, count: 8)
    }

    func close() {}
}

/// Fails every call, as a missing service would.
final class ThrowingTransport: SMCTransport {
    func call(request: [UInt8]) throws -> [UInt8] {
        throw SMC.SMCError.message("kernel said no")
    }

    func close() {}
}
