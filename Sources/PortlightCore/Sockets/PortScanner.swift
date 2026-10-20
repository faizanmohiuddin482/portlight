import Foundation

public struct ScanResult: Sendable {
    public let listening: [ListeningSocket]
    public let connections: [ConnectionKey: Int]

    public init(listening: [ListeningSocket], connections: [ConnectionKey: Int] = [:]) {
        self.listening = listening
        self.connections = connections
    }
}

public protocol PortScanning: Sendable {
    func scan() throws -> ScanResult
}

/// Lists every user's listening sockets with `netstat -anv`, which reports
/// pids without needing root.
public struct NetstatScanner: PortScanning {
    public init() {}

    public func scan() throws -> ScanResult {
        let tcp = try run(["-anv", "-p", "tcp"])
        return ScanResult(
            listening: NetstatParser.parse(tcp, proto: .tcp)
                + NetstatParser.parse(try run(["-anv", "-p", "udp"]), proto: .udp),
            connections: NetstatParser.connections(tcp)
        )
    }

    private func run(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
