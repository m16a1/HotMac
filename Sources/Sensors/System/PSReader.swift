import Foundation

/// Per-process CPU and memory for the processes the kernel will not describe to
/// us, read by running `/bin/ps`.
///
/// `ps` is an Apple platform binary carrying `com.apple.system-task-ports.read`,
/// the entitlement our ad-hoc signature cannot have, so it can read a process
/// owned by another user and we cannot. This is the host boundary for that read:
/// it spawns the process and hands its output to the pure
/// `ProcessUsageFallback.parse(_:)`. It is only ever asked about the handful of
/// processes the kernel hid, never about the whole process list, and only while
/// the Processes screen is on screen.
enum PSReader {
    /// Writing every field with a trailing `=` drops the header, so every line is
    /// one process and nothing has to be skipped.
    private static let format = "pid=,pcpu=,rss="

    /// The CPU and memory `ps` reports for each of `pids`. A pid that has exited
    /// by the time `ps` runs is simply absent, and a failure to run `ps` at all
    /// yields no figures rather than an error: the rows keep their dash.
    static func usage(for pids: [Int32]) -> [Int32: ProcessUsage] {
        guard !pids.isEmpty else { return [:] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = [
            "-o", format,
            "-p", pids.map { String($0) }.joined(separator: ","),
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return [:]
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessUsageFallback.parse(String(decoding: data, as: UTF8.self))
    }
}
