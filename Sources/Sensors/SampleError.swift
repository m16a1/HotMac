import Foundation

/// Why a sampling tick could not be completed.
///
/// Split by the stage that broke: a connection that never opened is a different
/// problem from a key table that could not be read, and the status screen can
/// say which one it was.
enum SampleError: Error, CustomStringConvertible {
    case connection(Error)
    case metadata(Error)

    var description: String {
        switch self {
        case .connection(let error):
            return "SMC connection failed: \(error)"
        case .metadata(let error):
            return "SMC key table failed: \(error)"
        }
    }
}
