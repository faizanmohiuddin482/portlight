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

@Test func ownerOfPort() {
    let e = PortCatalog.build([sock(.tcp, "*", 3000, pid: 7)], inspector: FakeInspector())
    #expect(FreePort.owner(of: 3000, in: e)?.pid == 7)
    #expect(FreePort.owner(of: 3001, in: e) == nil)
}
