import Foundation
import Testing
@testable import PortlightCore

@Test func scannerSeesOwnListener() throws {
    let (fd, port) = try listen(on: 0)
    defer { close(fd) }
    let s = try NetstatScanner().scan()
    #expect(s.contains { $0.port == port && $0.pid == getpid() && $0.reach == .local && $0.proto == .tcp })
}
