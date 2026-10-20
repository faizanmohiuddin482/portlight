import Foundation
import PortlightCore
import Testing
@testable import Portlight

/// Each scan() call takes the next scripted (delay, sockets) step.
final class ScriptedScanner: PortScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [(delay: TimeInterval, sockets: [ListeningSocket])]
    init(_ steps: [(delay: TimeInterval, sockets: [ListeningSocket])]) { self.steps = steps }
    func scan() throws -> [ListeningSocket] {
        let step = lock.withLock { steps.removeFirst() }
        Thread.sleep(forTimeInterval: step.delay)
        return step.sockets
    }
}

struct NoInspector: ProcessInspecting {
    func details(pid: Int32) -> ProcessDetails? { nil }
    func identity(pid: Int32) -> ProcessIdentity? { nil }
}

@MainActor @Test func olderScanCannotOverwriteNewer() async throws {
    let stale = ListeningSocket(proto: .tcp, address: "*", port: 3000, pid: 9, processName: "node")
    let scanner = ScriptedScanner([(0.3, [stale]), (0, [])])
    let store = PortStore(stayAwake: StayAwakeManager(), scanner: scanner, inspector: NoInspector())

    async let slow: Void = store.refresh()      // started first, finishes last
    try await Task.sleep(for: .milliseconds(50))
    await store.refresh()                       // newer scan: the process is gone
    await slow

    #expect(store.entries.isEmpty)
}
