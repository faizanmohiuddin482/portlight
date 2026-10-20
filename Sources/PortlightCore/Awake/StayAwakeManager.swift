import Foundation
import Observation

public struct AwakeHold: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let identity: ProcessIdentity
    public let processName: String
    /// nil = until the process exits.
    public let deadline: Date?
}

/// Keeps the Mac awake on behalf of specific processes. Each hold owns one
/// power assertion, released when the process exits, its timer ends, or
/// `stopAll()` runs (on app quit). The OS also drops assertions if we crash.
@MainActor @Observable
public final class StayAwakeManager {
    public private(set) var holds: [AwakeHold] = []
    public var isActive: Bool { !holds.isEmpty }

    @ObservationIgnored private let backend: SleepAssertionBackend
    @ObservationIgnored private var assertions: [UUID: UInt32] = [:]

    public init(backend: SleepAssertionBackend = IOPMBackend()) {
        self.backend = backend
    }

    public func start(_ identity: ProcessIdentity, name: String, duration: TimeInterval?, now: Date = .now) {
        if let existing = holds.first(where: { $0.identity == identity }) { stop(existing.id) }
        guard let assertion = backend.acquire(reason: "Portlight: keeping awake for \(name)") else { return }
        let hold = AwakeHold(
            id: UUID(), identity: identity, processName: name,
            deadline: duration.map { now.addingTimeInterval($0) }
        )
        assertions[hold.id] = assertion
        holds.append(hold)
    }

    public func stop(_ id: UUID) {
        if let assertion = assertions.removeValue(forKey: id) { backend.release(assertion) }
        holds.removeAll { $0.id == id }
    }

    public func stopAll() {
        for hold in holds { stop(hold.id) }
    }

    public func tick(now: Date, isAlive: (ProcessIdentity) -> Bool) {
        for hold in holds where !isAlive(hold.identity) || hold.deadline.map({ now >= $0 }) == true {
            stop(hold.id)
        }
    }
}
