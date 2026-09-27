import Foundation

/// One SMC connection together with the per-key metadata discovered with it.
///
/// A session owns the connection's lifetime: releasing it closes the client.
/// That is why a failed tick drops the whole session rather than mutating it.
struct SMCSession {
    /// Every temperature key, with how to decode its value.
    typealias Table = [String: (format: String, raw: [UInt8], littleEndian: Bool)]

    private let client: SMC
    private let meta: [String: SMC.KeyInfo]

    /// Connect and discover the key table in one step, so a session can never
    /// exist half-built. A failure is tagged with the stage that broke.
    init(connect: () throws -> SMC) throws {
        let client: SMC
        do {
            client = try connect()
        } catch {
            throw SampleError.connection(error)
        }
        let meta: [String: SMC.KeyInfo]
        do {
            meta = try client.collectTemperatureMeta()
        } catch {
            throw SampleError.metadata(error)
        }
        self.client = client
        self.meta = meta
    }

    /// Read every known temperature key. A key the kernel refuses is skipped:
    /// one unreadable key is not a failed tick.
    func readTable() -> Table {
        var table: Table = [:]
        for (key, info) in meta {
            if let raw = try? client.readValue(key, size: info.size) {
                table[key] = (info.format, raw, info.littleEndian)
            }
        }
        return table
    }
}
