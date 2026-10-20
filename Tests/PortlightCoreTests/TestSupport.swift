import Foundation
import Testing

func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try String(contentsOf: url, encoding: .utf8)
}

@testable import PortlightCore

func details(
    pid: Int32 = 10, cwd: String? = nil, args: [String] = [], path: String? = nil, uid: uid_t = getuid()
) -> ProcessDetails {
    ProcessDetails(
        identity: ProcessIdentity(pid: pid, startTime: 1), executablePath: path ?? args.first,
        arguments: args, workingDirectory: cwd, uid: uid, parentPid: 1
    )
}

func sock(_ proto: TransportProtocol, _ address: String, _ port: UInt16, pid: Int32) -> ListeningSocket {
    ListeningSocket(proto: proto, address: address, port: port, pid: pid, processName: "test")
}

final class FakeInspector: ProcessInspecting, @unchecked Sendable {
    var seeded: [Int32: ProcessDetails] = [:]
    private(set) var detailCalls: [Int32] = []
    func details(pid: Int32) -> ProcessDetails? { detailCalls.append(pid); return seeded[pid] }
    func identity(pid: Int32) -> ProcessIdentity? { seeded[pid]?.identity }
}

struct SocketError: Error { let errno: Int32 }

/// Opens a TCP listener on 127.0.0.1:`port` (0 = any free port). Returns (fd, port).
func listen(on port: UInt16) throws -> (Int32, UInt16) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard bound == 0, Darwin.listen(fd, 1) == 0 else { close(fd); throw SocketError(errno: errno) }
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
    }
    return (fd, UInt16(bigEndian: addr.sin_port))
}

func spawn(_ path: String, _ args: [String]) throws -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    try p.run()
    return p
}
