public enum TransportProtocol: String, Sendable {
    case tcp, udp
}

/// Whether a socket is reachable only from this Mac or from the network too.
public enum Reach: Sendable {
    case local, network

    public static func of(address: String) -> Reach {
        let a = address.lowercased()
        if a.hasPrefix("127.") || a == "::1" || a == "localhost" || a.hasPrefix("fe80::1%lo") {
            return .local
        }
        return .network
    }
}

/// A listening (TCP) or bound (UDP) socket as reported by `netstat`.
public struct ListeningSocket: Sendable, Hashable {
    public let proto: TransportProtocol
    public let address: String
    public let port: UInt16
    public let pid: Int32
    public let processName: String

    public init(proto: TransportProtocol, address: String, port: UInt16, pid: Int32, processName: String) {
        self.proto = proto
        self.address = address
        self.port = port
        self.pid = pid
        self.processName = processName
    }

    public var reach: Reach { .of(address: address) }
}
