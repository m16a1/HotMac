import Foundation
import Testing
@testable import Sensors

/// Parsing the `pid cpu rss` output of `ps`.
@Suite("Process usage fallback")
struct ProcessUsageFallbackTests {
    /// One process per line, right-aligned by `ps`, so the leading spaces must not
    /// become an empty field. `ps` reports RSS in 1024-byte units.
    @Test func parsesOneProcessPerLine() {
        let table = ProcessUsageFallback.parse("""
              1   0.0  30992
             98   0.7  12000
            170  31.5 271040
        """)

        #expect(table == [
            1: ProcessUsage(cpuPercent: 0.0, memoryBytes: 30_992 * 1024),
            98: ProcessUsage(cpuPercent: 0.7, memoryBytes: 12_000 * 1024),
            170: ProcessUsage(cpuPercent: 31.5, memoryBytes: 271_040 * 1024),
        ])
    }

    /// `ps` prints nothing when there is nothing to report, which must parse to
    /// nothing rather than to a row.
    @Test func anEmptyOutputParsesToNothing() {
        #expect(ProcessUsageFallback.parse("").isEmpty)
        #expect(ProcessUsageFallback.parse("\n").isEmpty)
    }

    /// A line that is not exactly three numbers is dropped, so a stray message on
    /// stdout cannot become a reading.
    @Test(arguments: [
        "ps: process id too large",
        "  170  31.5",
        "  170  31.5  1  extra",
        "  pid  cpu  rss",
        "  abc  31.5  100",
        "  170   abc  100",
        "  170  31.5   abc",
    ])
    func malformedLinesAreSkipped(_ line: String) {
        #expect(ProcessUsageFallback.parse(line).isEmpty)
    }

    /// A good line beside a bad one keeps the good one.
    @Test func aGoodLineSurvivesABadOne() {
        let table = ProcessUsageFallback.parse("  170  31.5  271040\nnonsense\n   1   0.0  30992")

        #expect(table == [
            170: ProcessUsage(cpuPercent: 31.5, memoryBytes: 271_040 * 1024),
            1: ProcessUsage(cpuPercent: 0.0, memoryBytes: 30_992 * 1024),
        ])
    }
}
