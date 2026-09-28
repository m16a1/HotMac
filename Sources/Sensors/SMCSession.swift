import Foundation

/// One SMC connection together with the per-key metadata discovered with it.
///
/// A session owns the connection's lifetime: releasing it closes the client.
/// That is why a failed tick drops the whole session rather than mutating it.
struct SMCSession {
    /// Some key family, with how to decode each value.
    typealias Table = [String: (format: String, raw: [UInt8], littleEndian: Bool)]

    private let client: SMC
    private let temperatureMeta: [String: SMC.KeyInfo]
    private let fanMeta: [String: SMC.KeyInfo]

    /// Connect and discover the key table in one step, so a session can never
    /// exist half-built. A failure is tagged with the stage that broke.
    init(connect: () throws -> SMC) throws {
        let client: SMC
        do {
            client = try connect()
        } catch {
            throw SampleError.connection(error)
        }
        let meta: SMC.CollectedMeta
        do {
            meta = try client.collectMeta()
        } catch {
            throw SampleError.metadata(error)
        }
        self.client = client
        self.temperatureMeta = meta.temperatures
        self.fanMeta = meta.fans
    }

    /// Read every known temperature key. A key the kernel refuses is skipped:
    /// one unreadable key is not a failed tick.
    func readTable() -> Table {
        read(temperatureMeta)
    }

    /// Read every known fan speed key, in the same shape as a temperature
    /// table so the two decode through the same path.
    func readFans() -> Table {
        read(fanMeta)
    }

    private func read(_ meta: [String: SMC.KeyInfo]) -> Table {
        var table: Table = [:]
        for (key, info) in meta {
            if let raw = try? client.readValue(key, size: info.size) {
                table[key] = (info.format, raw, info.littleEndian)
            }
        }
        return table
    }
}
