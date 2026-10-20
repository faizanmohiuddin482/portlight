import Foundation

public protocol PortScanning: Sendable {
    func scan() throws -> [ListeningSocket]
}

/// Lists every user's listening sockets with `netstat -anv`, which reports
/// `process:pid` without needing root.
public struct NetstatScanner: PortScanning {
    public init() {}

    public func scan() throws -> [ListeningSocket] {
        try NetstatParser.parse(run(["-anv", "-p", "tcp"]), proto: .tcp)
            + NetstatParser.parse(run(["-anv", "-p", "udp"]), proto: .udp)
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
