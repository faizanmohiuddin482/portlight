import Foundation
import Testing
@testable import PortlightCore

@Test func nearestFreeSkipsTaken() {
    #expect(FreePort.nearestFree(to: 3000, isFree: { $0 != 3001 }) == 3002)
    #expect(FreePort.nearestFree(to: 3000, isFree: { _ in false }) == nil)
}

@Test func nearestFreeStopsAtTopPort() {
    #expect(FreePort.nearestFree(to: 65535, isFree: { _ in true }) == nil)
}

@Test func ownerOfPort() {
    let e = PortCatalog.build([sock(.tcp, "*", 3000, pid: 7)], inspector: FakeInspector())
    #expect(FreePort.owner(of: 3000, in: e)?.pid == 7)
    #expect(FreePort.owner(of: 3001, in: e) == nil)
}

/// These open real sockets. Run them one at a time so a port one test just
/// released can't be handed to another test's listener mid-check.
@Suite(.serialized) struct RealSocketTests {
    @Test func scannerSeesOwnListener() throws {
        let (fd, port) = try listen(on: 0)
        defer { close(fd) }
        let s = try NetstatScanner().scan().listening
        #expect(s.contains { $0.port == port && $0.pid == getpid() && $0.reach == .local && $0.proto == .tcp })
    }

    @Test func canBindDetectsBusyPort() throws {
        let (fd, port) = try listen(on: 0)
        defer { close(fd) }
        #expect(FreePort.canBind(port) == false)
    }

    @Test func canBindDetectsWildcardListener() throws {
        let (fd, port) = try listen(on: 0, host: "0.0.0.0")
        defer { close(fd) }
        #expect(FreePort.canBind(port) == false)
    }

    @Test func canBindPortInTimeWait() throws {
        let (listener, port) = try listen(on: 0)
        let client = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        try #require(connected == 0)
        let server = accept(listener, nil, nil)
        close(server)      // server closes first, so its side of the port enters TIME_WAIT
        close(listener)
        usleep(50_000)
        close(client)
        #expect(FreePort.canBind(port) == true)
    }

    @Test func canBindFreePort() throws {
        let (fd, port) = try listen(on: 0)
        close(fd)
        #expect(FreePort.canBind(port) == true)
    }
}
