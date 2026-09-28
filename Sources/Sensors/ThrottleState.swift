import Foundation

/// How far the system is holding the CPU back because of heat, as the OS
/// reports it.
///
/// `nominal` means no restriction at all; the OS only raises the level once it
/// starts to limit performance, so anything above `nominal` is the machine
/// throttling itself. The cases mirror `ProcessInfo.ThermalState`, which lives
/// at the host boundary, so the mapping is pure and testable.
public enum ThrottleState: Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    /// Map the raw value `ProcessInfo.thermalState` reports, where `nominal`
    /// is 0 and the cases follow in the order above. A value outside that set
    /// reads as `nominal`, which is what an unconstrained machine reports.
    public init(thermalState: Int) {
        switch thermalState {
        case 1: self = .fair
        case 2: self = .serious
        case 3: self = .critical
        default: self = .nominal
        }
    }
}
