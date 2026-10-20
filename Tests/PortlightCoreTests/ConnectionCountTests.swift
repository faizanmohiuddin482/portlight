import Testing
@testable import PortlightCore

@Test(arguments: ["netstat-tcp.txt", "netstat-tcp-macos15.txt"])
func countsEstablished(_ file: String) throws {
    let c = NetstatParser.connections(try fixture(file))
    #expect(c.values.reduce(0, +) == 1)
    #expect(c[ConnectionKey(pid: file == "netstat-tcp.txt" ? 86926 : 2001, localPort: 57092)] == 1)
}
