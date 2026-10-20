public enum PortCatalog {
    /// Merges IPv4/IPv6 sockets for the same (proto, port, pid) into one entry,
    /// marked `.network` if any of them is reachable from the network.
    public static func build(_ sockets: [ListeningSocket], inspector: ProcessInspecting) -> [PortEntry] {
        struct Key: Hashable { let proto: TransportProtocol; let port: UInt16; let pid: Int32 }
        let groups = Dictionary(grouping: sockets) { Key(proto: $0.proto, port: $0.port, pid: $0.pid) }

        var detailsByPid: [Int32: ProcessDetails?] = [:]
        for pid in Set(sockets.map(\.pid)).sorted() {
            detailsByPid[pid] = inspector.details(pid: pid)
        }

        return groups.map { key, socks in
            let name = socks[0].processName
            let details = detailsByPid[key.pid] ?? nil
            return PortEntry(
                port: key.port,
                proto: key.proto,
                reach: socks.contains { $0.reach == .network } ? .network : .local,
                pid: key.pid,
                processName: name,
                project: ProjectResolver.resolve(processName: name, details: details),
                details: details
            )
        }
        .sorted { ($0.port, $0.proto.rawValue) < ($1.port, $1.proto.rawValue) }
    }
}
