import Foundation

/// The host's thermal-pressure reading, kept out of the pure layer.
///
/// This is the only place that consults `ProcessInfo`; the directory is the
/// project's marker for the host boundary, so `test.py` excludes it from the
/// coverage report.
extension ThrottleState {
    /// The throttling level the OS reports right now.
    public static func system() -> ThrottleState {
        ThrottleState(thermalState: ProcessInfo.processInfo.thermalState.rawValue)
    }
}
