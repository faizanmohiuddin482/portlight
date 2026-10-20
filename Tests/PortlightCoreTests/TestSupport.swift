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
