import Testing
@testable import PortlightCore

@Test func mergesDualStack() {
    let s = [sock(.tcp, "127.0.0.1", 3000, pid: 10), sock(.tcp, "*", 3000, pid: 10)]
    let e = PortCatalog.build(s, inspector: FakeInspector())
    #expect(e.count == 1)
    #expect(e[0].reach == .network)
}

@Test func keepsTcpAndUdpSeparate() {
    let s = [sock(.tcp, "*", 5353, pid: 10), sock(.udp, "*", 5353, pid: 10)]
    #expect(PortCatalog.build(s, inspector: FakeInspector()).count == 2)
}

@Test func entryWithoutDetails() {
    let e = PortCatalog.build([sock(.tcp, "*", 7000, pid: 999_999)], inspector: FakeInspector())
    #expect(e[0].details == nil)
    #expect(e[0].project.label == "test")
}

@Test func sortsByPort() {
    let e = PortCatalog.build([sock(.tcp, "*", 8000, pid: 1), sock(.tcp, "*", 3000, pid: 2)], inspector: FakeInspector())
    #expect(e.map(\.port) == [3000, 8000])
}

@Test func inspectsEachPidOnce() {
    let f = FakeInspector()
    _ = PortCatalog.build([sock(.tcp, "*", 3000, pid: 5), sock(.tcp, "*", 9229, pid: 5)], inspector: f)
    #expect(f.detailCalls == [5])
}
