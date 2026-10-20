import Foundation

public struct ConnectionKey: Sendable, Hashable {
    public let pid: Int32
    public let localPort: UInt16

    public init(pid: Int32, localPort: UInt16) {
        self.pid = pid
        self.localPort = localPort
    }
}

/// Parses `netstat -anv -p tcp|udp` output.
///
/// The columns differ between macOS versions: newer releases print a
/// `process:pid` column (name truncated, may contain spaces), macOS 14/15
/// print `pid epid` with no name, and macOS 14 has no rxbytes/txbytes.
/// So the layout is read from the header: the columns before the pid column
/// are counted from the left, and those after it from the right.
public enum NetstatParser {
    struct Layout {
        /// Header columns before the pid column ("Local Address" counts as one).
        let before: Int
        /// Header columns after the pid column.
        let after: Int
        /// Whether the pid column is `process:pid`.
        let hasName: Bool
    }

    struct Row {
        let address: String
        let port: UInt16
        let foreign: Substring
        let state: Substring?
        let pid: Int32
        let name: String
    }

    /// Listening TCP sockets, or bound (unconnected) UDP sockets.
    public static func parse(_ output: String, proto: TransportProtocol) -> [ListeningSocket] {
        rows(output, proto: proto).compactMap { row in
            switch proto {
            case .tcp: guard row.state == "LISTEN" else { return nil }
            case .udp: guard row.foreign == "*.*" else { return nil }
            }
            return ListeningSocket(proto: proto, address: row.address, port: row.port, pid: row.pid, processName: row.name)
        }
    }

    /// Established TCP connections counted by (pid, local port).
    public static func connections(_ tcpOutput: String) -> [ConnectionKey: Int] {
        rows(tcpOutput, proto: .tcp)
            .filter { $0.state == "ESTABLISHED" }
            .reduce(into: [:]) { counts, row in counts[ConnectionKey(pid: row.pid, localPort: row.port), default: 0] += 1 }
    }

    static func layout(header: Substring) -> Layout? {
        let cols = header
            .replacingOccurrences(of: "Local Address", with: "Local")
            .replacingOccurrences(of: "Foreign Address", with: "Foreign")
            .split(whereSeparator: \.isWhitespace)
        guard let i = cols.firstIndex(where: { $0 == "pid" || $0 == "process:pid" }) else { return nil }
        return Layout(before: i, after: cols.count - i - 1, hasName: cols[i] == "process:pid")
    }

    private static func rows(_ output: String, proto: TransportProtocol) -> [Row] {
        let lines = output.split(separator: "\n")
        guard let header = lines.first(where: { $0.hasPrefix("Proto") }), let layout = layout(header: header) else {
            return []
        }
        return lines.compactMap { row(in: $0, layout: layout, proto: proto) }
    }

    private static func row(in line: Substring, layout: Layout, proto: TransportProtocol) -> Row? {
        guard line.hasPrefix(proto.rawValue) else { return nil }
        let tokens = line.split(whereSeparator: \.isWhitespace)
        // UDP rows leave the (state) column empty, so they have one token fewer before the pid.
        let before = layout.before - (proto == .udp ? 1 : 0)
        let pidIndex = tokens.count - 1 - layout.after
        guard tokens.count > 5, pidIndex >= before else { return nil }

        var name = ""
        var pidText = tokens[pidIndex]
        if layout.hasName {
            guard let colon = pidText.lastIndex(of: ":") else { return nil }
            let words = tokens[before..<pidIndex].map(String.init) + [String(pidText[..<colon])]
            name = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            pidText = pidText[pidText.index(after: colon)...]
        }

        let local = tokens[3]
        guard let dot = local.lastIndex(of: "."),
              let port = UInt16(local[local.index(after: dot)...]),
              let pid = Int32(pidText)
        else { return nil }
        return Row(
            address: String(local[..<dot]), port: port, foreign: tokens[4],
            state: proto == .tcp ? tokens[5] : nil, pid: pid, name: name
        )
    }
}
