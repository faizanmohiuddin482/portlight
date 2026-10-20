import Foundation

/// Parses `netstat -anv -p tcp|udp` output.
///
/// Columns: proto, recv-q, send-q, local, foreign, [state — tcp only],
/// rxbytes, txbytes, rhiwat, shiwat, process:pid, … The process name may
/// contain spaces and is truncated by netstat, so it's taken as everything
/// between the four counters and the last `:pid`.
public enum NetstatParser {
    nonisolated(unsafe) private static let tcpLine =
        /^tcp\S*\s+\d+\s+\d+\s+(\S+)\s+(\S+)\s+(\S+)\s+\d+\s+\d+\s+\d+\s+\d+\s+(.+?):(\d+)\s/
    nonisolated(unsafe) private static let udpLine =
        /^udp\S*\s+\d+\s+\d+\s+(\S+)\s+(\S+)\s+\d+\s+\d+\s+\d+\s+\d+\s+(.+?):(\d+)\s/

    public static func parse(_ output: String, proto: TransportProtocol) -> [ListeningSocket] {
        output.split(separator: "\n").compactMap { line in
            switch proto {
            case .tcp:
                guard let m = try? tcpLine.prefixMatch(in: line), m.3 == "LISTEN" else { return nil }
                return socket(.tcp, local: m.1, name: m.4, pid: m.5)
            case .udp:
                guard let m = try? udpLine.prefixMatch(in: line), m.2 == "*.*" else { return nil }
                return socket(.udp, local: m.1, name: m.3, pid: m.4)
            }
        }
    }

    private static func socket(
        _ proto: TransportProtocol, local: Substring, name: Substring, pid: Substring
    ) -> ListeningSocket? {
        guard let dot = local.lastIndex(of: "."),
              let port = UInt16(local[local.index(after: dot)...]),
              let pid = Int32(pid)
        else { return nil }
        return ListeningSocket(
            proto: proto,
            address: String(local[..<dot]),
            port: port,
            pid: pid,
            processName: name.trimmingCharacters(in: .whitespaces)
        )
    }
}
