import Darwin

public enum QuitPolicy {
    static let protectedPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/"]

    /// Only the current user's own, non-system processes get a quit button.
    public static func canQuit(_ details: ProcessDetails?, currentUID: uid_t = getuid(), selfPid: Int32 = getpid()) -> Bool {
        guard let details, details.uid == currentUID else { return false }
        let pid = details.identity.pid
        guard pid > 1, pid != selfPid else { return false }
        let path = details.executablePath ?? ""
        return !protectedPrefixes.contains { path.hasPrefix($0) }
    }
}

public enum TerminateResult: Sendable, Equatable {
    case exited, stillRunning, failed(Int32)
}

public struct ProcessController: Sendable {
    private let inspector: ProcessInspecting

    public init(inspector: ProcessInspecting = ProcessInspector()) {
        self.inspector = inspector
    }

    public func isAlive(_ identity: ProcessIdentity) -> Bool {
        inspector.identity(pid: identity.pid) == identity
    }

    /// Sends SIGTERM and waits up to `grace` for the process to go away.
    public func terminate(_ identity: ProcessIdentity, grace: Duration = .seconds(3)) async -> TerminateResult {
        if let failure = signal(identity, SIGTERM) { return failure }
        let deadline = ContinuousClock.now + grace
        while ContinuousClock.now < deadline {
            if !isAlive(identity) { return .exited }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return isAlive(identity) ? .stillRunning : .exited
    }

    public func forceKill(_ identity: ProcessIdentity) -> TerminateResult {
        if let failure = signal(identity, SIGKILL) { return failure }
        for _ in 0..<20 where isAlive(identity) { usleep(50_000) }
        return isAlive(identity) ? .stillRunning : .exited
    }

    /// Returns a final result if no wait is needed; never signals a recycled PID.
    private func signal(_ identity: ProcessIdentity, _ sig: Int32) -> TerminateResult? {
        guard isAlive(identity) else { return .exited }
        guard kill(identity.pid, sig) == 0 else { return errno == ESRCH ? .exited : .failed(errno) }
        return nil
    }
}
