import Testing
@testable import Sensors

/// Everything the client does when the kernel answers badly: refused reads, a
/// response too short to carry a result, and a malformed key.
@Suite("SMC failures")
struct SMCFailureTests {
    @Test func errorDescriptionsCarryTheirMeaning() {
        let cases: [(SMC.SMCError, String)] = [
            (.serviceNotFound, "no AppleSMC service"),
            (.openFailed(0x2c7), "unsupported"),
            (.openFailed(0x999), "0x999"),
            (.operationFailed(0), "success"),
            (.message("boom"), "boom"),
        ]
        for (error, fragment) in cases {
            #expect("\(error)".contains(fragment), "\(error)")
        }
    }

    @Test func aShortResponseYieldsNoKey() {
        #expect((try? SMC(transport: TruncatedTransport()).indexKey(0)) == nil)
    }

    @Test func aShortResponseThrowsOnRead() {
        let smc = SMC(transport: TruncatedTransport())
        #expect(throws: SMC.SMCError.self) {
            _ = try smc.readValue("Tp00", size: 4)
        }
    }

    @Test func aShortResponseThrowsOnKeyInfo() {
        let smc = SMC(transport: TruncatedTransport())
        #expect(throws: SMC.SMCError.self) {
            _ = try smc.keyInfo("Tp00")
        }
    }

    @Test func aRefusedReadThrows() {
        let smc = SMC(transport: FakeSMCTransport(order: [], table: [:]))
        #expect(throws: SMC.SMCError.self) {
            _ = try smc.readValue("Tp00", size: 4)
        }
    }

    @Test func aRefusedKeyInfoThrows() {
        let smc = SMC(transport: FakeSMCTransport(order: [], table: [:]))
        #expect(throws: SMC.SMCError.self) {
            _ = try smc.keyInfo("Tp00")
        }
    }

    @Test func aShortKeyIsRejected() {
        let smc = SMC(transport: FakeSMCTransport(order: [], table: [:]))
        #expect {
            _ = try smc.readValue("Tf0", size: 4)
        } throws: { error in
            "\(error)".contains("exactly 4 characters")
        }
    }
}
