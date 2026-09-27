// swift-tools-version: 6.0
import Foundation
import PackageDescription

/// The suite is an executable target, not a `.testTarget`, because `swift test`
/// cannot run swift-testing in a Command Line Tools-only install: SwiftPM builds
/// the `.xctest` bundle but has no `xctest` host to load it, and the fallback
/// `swiftpm-testing-helper` only scans the *main* image for tests, so the run
/// silently reports zero tests and exits 0.
///
/// A test in the main image is discovered normally, so `Tests/SensorsTests` is
/// built as an executable with `TestRunner.swift` as its entry point.
let searchRoots = [
    ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
    "/Library/Developer/CommandLineTools",
    "/Applications/Xcode.app/Contents/Developer",
].compactMap { $0 }

let candidateDirectories = searchRoots.flatMap { root in
    [
        "\(root)/Library/Developer/usr/lib",
        "\(root)/Library/Developer/Frameworks",
        "\(root)/usr/lib/swift/macosx",
        "\(root)/Platforms/MacOSX.platform/Developer/usr/lib",
        "\(root)/Platforms/MacOSX.platform/Developer/Library/Frameworks",
        "\(root)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx",
    ]
}.filter { FileManager.default.fileExists(atPath: $0) }

func directoriesContaining(_ entry: String) -> [String] {
    candidateDirectories.filter { FileManager.default.fileExists(atPath: "\($0)/\(entry)") }
}

/// swift-testing needs three things SwiftPM does not add outside a test target:
///
/// - `Testing.framework` on the module search path, for `import Testing`;
/// - `lib_TestingInterop.dylib` on the runtime path, because Testing.framework
///   links against it and the copy in the Command Line Tools sits in
///   `Library/Developer/usr/lib`, which is not one of the paths it searches;
/// - the macro plugin, so `#expect` and `@Test` expand at all. SwiftPM adds
///   that `-plugin-path` itself for a `.testTarget`, which is the other reason
///   the suite cannot be one.
let frameworkDirectories = directoriesContaining("Testing.framework")
let runtimeDirectories = frameworkDirectories + directoriesContaining("lib_TestingInterop.dylib")

let pluginDirectories = searchRoots.flatMap { root in
    [
        "\(root)/usr/lib/swift/host/plugins/testing",
        "\(root)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing",
    ]
}.filter { FileManager.default.fileExists(atPath: $0) }

let testingCompileFlags = frameworkDirectories.flatMap { ["-F", $0] }
    + pluginDirectories.flatMap { ["-plugin-path", $0] }
let testingRuntimeFlags = runtimeDirectories.flatMap { ["-Xlinker", "-rpath", "-Xlinker", $0] }
let testingLinkFlags = testingCompileFlags + testingRuntimeFlags

let package = Package(
    name: "HotMac",
    platforms: [.macOS(.v14)],
    targets: [
        // The data layer: hardware access, key mapping, sampling. Deliberately
        // has no SwiftUI dependency, so it can be unit-tested without a host app.
        .target(
            name: "Sensors",
            path: "Sources/Sensors",
            swiftSettings: [
                // `TemperatureModel.loadPreviewData()` is DEBUG-only.
                .define("DEBUG", .when(configuration: .debug))
            ],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // The app itself.
        .executableTarget(
            name: "HotMac",
            dependencies: ["Sensors"],
            path: "Sources/UI",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("Charts"),
            ]
        ),
        // The suite. Run it with `./test.py`, or `swift run SensorsTests`.
        .executableTarget(
            name: "SensorsTests",
            dependencies: ["Sensors"],
            path: "Tests/SensorsTests",
            swiftSettings: testingCompileFlags.isEmpty ? [] : [.unsafeFlags(testingCompileFlags)],
            // The `-F` flags are needed again at link time so autolinking finds
            // Testing.framework, plus the rpaths so it and its interop library
            // resolve at launch.
            linkerSettings: testingLinkFlags.isEmpty ? [] : [.unsafeFlags(testingLinkFlags)]
        ),
    ]
)
