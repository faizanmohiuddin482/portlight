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
        let s = try NetstatScanner().scan()
        #expect(s.contains { $0.port == port && $0.pid == getpid() && $0.reach == .local && $0.proto == .tcp })
    }

    @Test func canBindDetectsBusyPort() throws {
        let (fd, port) = try listen(on: 0)
        defer { close(fd) }
        #expect(FreePort.canBind(port) == false)
    }

    @Test func canBindFreePort() throws {
        let (fd, port) = try listen(on: 0)
        close(fd)
        #expect(FreePort.canBind(port) == true)
    }
}
