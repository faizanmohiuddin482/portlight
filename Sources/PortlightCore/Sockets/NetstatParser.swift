import Foundation

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

    static func layout(header: Substring) -> Layout? {
        let cols = header
            .replacingOccurrences(of: "Local Address", with: "Local")
            .replacingOccurrences(of: "Foreign Address", with: "Foreign")
            .split(whereSeparator: \.isWhitespace)
        guard let i = cols.firstIndex(where: { $0 == "pid" || $0 == "process:pid" }) else { return nil }
        return Layout(before: i, after: cols.count - i - 1, hasName: cols[i] == "process:pid")
    }

    public static func parse(_ output: String, proto: TransportProtocol) -> [ListeningSocket] {
        let lines = output.split(separator: "\n")
        guard let header = lines.first(where: { $0.hasPrefix("Proto") }), let layout = layout(header: header) else {
            return []
        }
        return lines.compactMap { socket(in: $0, layout: layout, proto: proto) }
    }

    private static func socket(in line: Substring, layout: Layout, proto: TransportProtocol) -> ListeningSocket? {
        guard line.hasPrefix(proto.rawValue) else { return nil }
        let tokens = line.split(whereSeparator: \.isWhitespace)
        // UDP rows leave the (state) column empty, so they have one token fewer before the pid.
        let before = layout.before - (proto == .udp ? 1 : 0)
        let pidIndex = tokens.count - 1 - layout.after
        guard tokens.count > 5, pidIndex >= before else { return nil }

        switch proto {
        case .tcp: guard tokens[5] == "LISTEN" else { return nil }
        case .udp: guard tokens[4] == "*.*" else { return nil }
        }

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
        return ListeningSocket(proto: proto, address: String(local[..<dot]), port: port, pid: pid, processName: name)
    }
}
