import Testing
@testable import Sensors

/// The bytes the protocol client puts on the wire, and the connection it holds
/// open around them.
@Suite("SMC requests")
struct SMCRequestTests {
    @Test func temperatureKeysStartWithT() {
        #expect(SMC.temperaturePrefix == "T")
    }

    @Test func aReadSlicesTheValueFromOffset48() throws {
        let transport = FakeSMCTransport(order: [], table: ["Tf06": floatEntry(42.5)])
        let smc = SMC(transport: transport)

        #expect(try smc.readValue("Tf06", size: 4) == Wire.float(42.5))
    }

    @Test func aReadCarriesTheKeyTheSizeAndTheOperation() throws {
        let transport = FakeSMCTransport(order: [], table: ["Tf06": floatEntry(42.5)])
        let smc = SMC(transport: transport)
        _ = try smc.readValue("Tf06", size: 4)

        let request = try #require(transport.requests.last)
        #expect(Array(request[0..<4]) == Wire.fourcc("Tf06"))
        #expect(Array(request[28..<32]) == Wire.uint32(4))
        #expect(request[42] == 5)
    }

    @Test func aSmallValueUsesTheFixedSizeRequest() throws {
        let transport = FakeSMCTransport(order: [], table: ["Tf06": floatEntry(42.5)])
        let smc = SMC(transport: transport)
        _ = try smc.readValue("Tf06", size: 4)

        #expect(transport.requests.last?.count == 80)
    }

    @Test func aLargeValueSizesTheRequestToTheValue() {
        let transport = FakeSMCTransport(
            order: [],
            table: ["RVER": ("ch8*", [UInt8](repeating: 65, count: 120), true)]
        )
        _ = try? SMC(transport: transport).readValue("RVER", size: 120)

        #expect(transport.requests.last?.count == 168)
    }

    @Test func keyInfoComesFromTheResponse() throws {
        let transport = FakeSMCTransport(order: [], table: ["Tf06": floatEntry(42.5)])
        let smc = SMC(transport: transport)

        let info = try smc.keyInfo("Tf06")
        #expect(info.size == 4)
        #expect(info.format == "flt ")
        #expect(info.littleEndian)
        #expect(transport.requests.last?[42] == 9)
    }

    @Test func aBigEndianKeySetsNoEndiannessFlag() throws {
        let transport = FakeSMCTransport(order: [], table: ["#KEY": ("ui32", Wire.uint32(3669), false)])

        #expect(try SMC(transport: transport).keyInfo("#KEY").littleEndian == false)
    }

    @Test func closeReachesTheTransport() {
        let transport = FakeSMCTransport(order: [], table: [:])
        let smc = SMC(transport: transport)

        smc.close()
        #expect(transport.closeCount == 1)
    }

    @Test func deinitClosesTheTransport() {
        let transport = FakeSMCTransport(order: [], table: [:])
        var smc: SMC? = SMC(transport: transport)
        smc?.close()

        smc = nil
        #expect(transport.closeCount == 2)
    }
}
