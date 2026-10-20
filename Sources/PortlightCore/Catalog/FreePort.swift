import Darwin

public enum FreePort {
    public static func owner(of port: UInt16, in entries: [PortEntry]) -> PortEntry? {
        entries.first { $0.port == port && $0.proto == .tcp } ?? entries.first { $0.port == port }
    }

    /// True only if a TCP socket can bind the port on both the wildcard and
    /// loopback addresses — i.e. a dev server could start there right now.
    public static func canBind(_ port: UInt16) -> Bool {
        tryBind(port, INADDR_ANY) && tryBind(port, INADDR_LOOPBACK)
    }

    /// Searches upward from `port + 1`, the way dev servers fall back (3000 → 3001).
    public static func nearestFree(to port: UInt16, isFree: (UInt16) -> Bool, limit: Int = 100) -> UInt16? {
        let top = min(Int(port) + limit, Int(UInt16.max))
        guard Int(port) < top else { return nil }
        return (Int(port) + 1 ... top).lazy.map { UInt16($0) }.first(where: isFree)
    }

    private static func tryBind(_ port: UInt16, _ host: in_addr_t) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = host.bigEndian
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
