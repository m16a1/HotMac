import Testing

/// The suite's entry point.
///
/// This is an executable target rather than a `.testTarget`, because `swift
/// test` cannot run swift-testing with only the Command Line Tools installed
/// (see Package.swift). Running the tests in the main image is the part that
/// works, so `Tests/SensorsTests` is built as an executable and this is its
/// `main`.
///
/// `__swiftPMEntryPoint` is the entry point SwiftPM's own generated test runner
/// calls; the `as Never` picks the overload that terminates the process with the
/// suite's exit status rather than returning a count.
@main
struct TestRunner {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}
