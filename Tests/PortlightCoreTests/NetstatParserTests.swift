import Testing
@testable import PortlightCore

@Test func parsesListenersOnly() throws {
    let s = NetstatParser.parse(try fixture("netstat-tcp.txt"), proto: .tcp)
    #expect(s.map(\.port) == [3000, 8000, 5432, 7000])
}

@Test func parsesNamesWithSpaces() throws {
    let s = NetstatParser.parse(try fixture("netstat-tcp.txt"), proto: .tcp)
    #expect(s.last?.processName == "Google Chrome He")
    #expect(s.last?.pid == 86926)
}

@Test func parsesIPv6Address() throws {
    let s = NetstatParser.parse(try fixture("netstat-tcp.txt"), proto: .tcp)
    #expect(s.first { $0.port == 5432 }?.address == "::1")
}

@Test func reachFromAddress() {
    #expect(Reach.of(address: "127.0.0.1") == .local)
    #expect(Reach.of(address: "::1") == .local)
    #expect(Reach.of(address: "*") == .network)
    #expect(Reach.of(address: "192.168.1.10") == .network)
}

@Test func parsesUdpBoundSockets() throws {
    let s = NetstatParser.parse(try fixture("netstat-udp.txt"), proto: .udp)
    #expect(s.count == 3)
    #expect(s.first { $0.port == 53 }?.reach == .local)
}

@Test func ignoresGarbage() {
    #expect(NetstatParser.parse("nonsense\n\n", proto: .tcp).isEmpty)
}
