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

// macOS 14/15 print `pid epid` instead of `process:pid`, and macOS 14 has no
// rxbytes/txbytes columns. The parser must follow the header, not fixed offsets.
@Test(arguments: ["netstat-tcp-macos15.txt", "netstat-tcp-macos14.txt"])
func parsesPidOnlyFormats(_ file: String) throws {
    let s = NetstatParser.parse(try fixture(file), proto: .tcp)
    try #require(s.map(\.port) == [8765, 22, 22])
    #expect(s[0].pid == 1728)
    #expect(s[0].processName == "")
    #expect(s[0].reach == .local)
    #expect(s[1].pid == 1)
}

@Test func parsesPidOnlyUdp() throws {
    let s = NetstatParser.parse(try fixture("netstat-udp-macos14.txt"), proto: .udp)
    try #require(s.map(\.port) == [5353])
    #expect(s[0].pid == 400)
}
