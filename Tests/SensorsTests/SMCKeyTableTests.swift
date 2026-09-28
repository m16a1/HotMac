import Testing
@testable import Sensors

/// Walking the key table once to learn every temperature key's size, format and
/// byte order.
@Suite("SMC key table")
struct SMCKeyTableTests {
    private let table: TemperatureTable = [
        "Tp00": floatEntry(45.0),
        // Neither a temperature sensor nor a fan speed key, so the walk skips it.
        "B0AT": floatEntry(33.0),
        "Tg0a": floatEntry(40.0),
        "F0Ac": floatEntry(1350.0),
        "F0Mx": floatEntry(5349.0),
        // A fan key, but not one of the speed keys, so it is skipped too.
        "F0Tg": floatEntry(0.0),
    ]

    private var walker: SMC {
        SMC(transport: FakeSMCTransport(
            order: ["Tp00", "B0AT", "Tg0a", "F0Ac", "F0Mx", "F0Tg"],
            table: table
        ))
    }

    @Test func theWalkKeepsOnlyTemperatureKeys() throws {
        #expect(try walker.collectMeta().temperatures.keys.sorted() == ["Tg0a", "Tp00"])
    }

    @Test func theWalkAlsoKeepsTheFanSpeedKeys() throws {
        #expect(try walker.collectMeta().fans.keys.sorted() == ["F0Ac", "F0Mx"])
    }

    @Test func theWalkRecordsEachKeySize() throws {
        #expect(try walker.collectMeta().temperatures["Tp00"]?.size == 4)
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

        #expect(try gap.collectMeta().temperatures.keys.sorted() == ["Tp00"])
    }

    /// The same holds for a fan speed key the kernel refuses.
    @Test func aFanSpeedKeyTheKernelRefusesIsSkipped() throws {
        let gap = SMC(transport: FakeSMCTransport(
            order: ["F0Ac", "F0Mx"],
            table: ["F0Ac": floatEntry(1350.0), "F0Mx": floatEntry(5349.0)],
            missingInfoKeys: ["F0Mx"]
        ))

        #expect(try gap.collectMeta().fans.keys.sorted() == ["F0Ac"])
    }

    @Test func fourccSurvivesTheWireOrder() {
        #expect(SMC.decodeFourCC(Wire.fourcc("Tf06")) == "Tf06")
    }

    @Test func aShortFourccDecodesToNothing() {
        #expect(SMC.decodeFourCC([0x54, 0x66]) == "")
    }
}
