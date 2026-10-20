import Darwin

/// A PID plus its start time, so a recycled PID is never mistaken for the
/// process we were tracking.
public struct ProcessIdentity: Sendable, Hashable {
    public let pid: Int32
    public let startTime: UInt64

    public init(pid: Int32, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }
}

public struct ProcessDetails: Sendable, Equatable {
    public let identity: ProcessIdentity
    public let executablePath: String?
    /// Full argv including argv[0]; empty when we may not read it.
    public let arguments: [String]
    public let workingDirectory: String?
    public let uid: uid_t
    public let parentPid: Int32

    public init(
        identity: ProcessIdentity, executablePath: String?, arguments: [String],
        workingDirectory: String?, uid: uid_t, parentPid: Int32
    ) {
        self.identity = identity
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.uid = uid
        self.parentPid = parentPid
    }
}

public protocol ProcessInspecting: Sendable {
    func details(pid: Int32) -> ProcessDetails?
    func identity(pid: Int32) -> ProcessIdentity?
}
