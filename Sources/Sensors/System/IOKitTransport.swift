import Foundation
import IOKit

/// The only code in the app that talks to the kernel.
///
/// Everything here needs a real AppleSMC service and the IOKit user client, so
/// none of it can run in the test harness: this file is excluded from the
/// coverage report by `test.py`.
final class IOKitTransport: SMCTransport {
    private static let serviceName = "AppleSMC"

    // Method 0 opens an access window and method 1 closes it; both bracket every
    // struct call and take no arguments. The struct call itself goes through
    // method 2, whatever the sub-operation in `data8`.
    private static let selBegin: UInt32 = 0
    private static let selEnd: UInt32 = 1
    private static let selOperation: UInt32 = 2

    private var service: io_service_t = 0
    private var connection: io_connect_t = 0

    init() throws {
        // IOServiceMatching takes a C string here, not a CFStringRef. Passing a
        // CFString makes IOKit read the object header as the class name and
        // match nothing.
        guard let matching = IOServiceMatching(Self.serviceName) else {
            throw SMC.SMCError.serviceNotFound
        }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard svc != 0 else { throw SMC.SMCError.serviceNotFound }
        var conn: io_connect_t = 0
        // The real task port is required; 0 fails with kIOReturnError.
        let kr = IOServiceOpen(svc, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else {
            IOObjectRelease(svc)
            throw SMC.SMCError.openFailed(kr)
        }
        self.service = svc
        self.connection = conn
    }

    deinit {
        close()
    }

    func call(request: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: request.count)
        var outSize = request.count

        _ = IOConnectCallMethod(connection, Self.selBegin, nil, 0, nil, 0, nil, nil, nil, nil)
        let kr = request.withUnsafeBytes { inPtr -> kern_return_t in
            output.withUnsafeMutableBytes { outPtr -> kern_return_t in
                IOConnectCallStructMethod(
                    connection,
                    Self.selOperation,
                    inPtr.baseAddress,
                    request.count,
                    outPtr.baseAddress,
                    &outSize
                )
            }
        }
        _ = IOConnectCallMethod(connection, Self.selEnd, nil, 0, nil, 0, nil, nil, nil, nil)

        guard kr == KERN_SUCCESS else { throw SMC.SMCError.operationFailed(kr) }
        return Array(output[0..<outSize])
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }
    }
}

extension SMC {
    /// Connect to the real AppleSMC service.
    ///
    /// Lives here so that `SMC.swift` contains no kernel calls at all and the
    /// whole of the protocol logic stays testable.
    convenience init() throws {
        try self.init(transport: IOKitTransport())
    }
}
