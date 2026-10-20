import Foundation

public struct ActivitySample: Sendable {
    public let identity: ProcessIdentity
    public let ports: [UInt16]
    public let cpuTime: TimeInterval?

    public init(identity: ProcessIdentity, ports: [UInt16], cpuTime: TimeInterval?) {
        self.identity = identity
        self.ports = ports
        self.cpuTime = cpuTime
    }
}

/// Remembers when each listening process was last active: it had an
/// established connection, or used more than a trickle of CPU. Portlight has
/// no history before it first sees a process, so first sight counts as active.
public struct ActivityTracker: Sendable {
    /// CPU seconds per wall-clock second below which a process counts as idle (1 s per hour).
    public static let cpuIdleRate: Double = 1.0 / 3600

    private struct State: Sendable {
        var lastActive: Date
        var lastSample: Date
        var cpuTime: TimeInterval?
    }

    private var states: [ProcessIdentity: State] = [:]

    public init() {}

    public func lastActive(_ identity: ProcessIdentity) -> Date? {
        states[identity]?.lastActive
    }

    public mutating func record(_ samples: [ActivitySample], connections: [ConnectionKey: Int], now: Date) {
        var next: [ProcessIdentity: State] = [:]
        for sample in samples {
            guard var state = states[sample.identity] else {
                next[sample.identity] = State(lastActive: now, lastSample: now, cpuTime: sample.cpuTime)
                continue
            }
            let connected = sample.ports.contains {
                connections[ConnectionKey(pid: sample.identity.pid, localPort: $0), default: 0] > 0
            }
            let busy: Bool = {
                guard let cpu = sample.cpuTime, let before = state.cpuTime else { return false }
                return cpu - before > Self.cpuIdleRate * now.timeIntervalSince(state.lastSample)
            }()
            if connected || busy { state.lastActive = now }
            state.lastSample = now
            state.cpuTime = sample.cpuTime
            next[sample.identity] = state
        }
        states = next
    }
}
