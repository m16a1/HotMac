import Testing
@testable import Sensors

/// Walking the key table once to learn every temperature key's size, format and
/// byte order.
@Suite("SMC key table")
struct SMCKeyTableTests {
    private let table: TemperatureTable = [
        "Tp00": floatEntry(45.0),
        // Not a temperature key, so the walk must skip it.
        "B0AT": floatEntry(33.0),
        "Tg0a": floatEntry(40.0),
    ]

    private var walker: SMC {
        SMC(transport: FakeSMCTransport(order: ["Tp00", "B0AT", "Tg0a"], table: table))
    }

    @Test func theWalkKeepsOnlyTemperatureKeys() throws {
        #expect(try walker.collectTemperatureMeta().keys.sorted() == ["Tg0a", "Tp00"])
    }

    @Test func theWalkRecordsEachKeySize() throws {
        #expect(try walker.collectTemperatureMeta()["Tp00"]?.size == 4)
    }

    @Test func indexZeroIsTheFirstKey() throws {
        #expect(try walker.indexKey(0) == "Tp00")
    }

    @Test func anEmptyIndexSlotIsNil() throws {
        #expect(try walker.indexKey(99) == nil)
    }

    /// A key the kernel refuses to describe is skipped, not fatal.
    @Test func aKeyTheKernelRefusesIsSkipped() throws {
        let gap = SMC(transport: FakeSMCTransport(
            order: ["Tp00", "Tdead"],
            table: ["Tp00": floatEntry(45.0)],
            missingInfoKeys: ["Tdead"]
        ))

        #expect(try gap.collectTemperatureMeta().keys.sorted() == ["Tp00"])
    }

    @Test func fourccSurvivesTheWireOrder() {
        #expect(SMC.decodeFourCC(Wire.fourcc("Tf06")) == "Tf06")
    }

    @Test func aShortFourccDecodesToNothing() {
        #expect(SMC.decodeFourCC([0x54, 0x66]) == "")
    }
}
