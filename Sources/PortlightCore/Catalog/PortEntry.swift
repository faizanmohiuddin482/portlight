/// One row in Portlight: a port held by a process.
public struct PortEntry: Sendable, Identifiable, Equatable {
    public var id: String { "\(proto.rawValue):\(port):\(pid)" }
    public let port: UInt16
    public let proto: TransportProtocol
    public let reach: Reach
    public let pid: Int32
    public let processName: String
    public let project: ProjectInfo
    public let details: ProcessDetails?

    public init(
        port: UInt16, proto: TransportProtocol, reach: Reach, pid: Int32,
        processName: String, project: ProjectInfo, details: ProcessDetails?
    ) {
        self.port = port
        self.proto = proto
        self.reach = reach
        self.pid = pid
        self.processName = processName
        self.project = project
        self.details = details
    }
}
