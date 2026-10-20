import Testing
@testable import PortlightCore

@Test func parsesAssertions() throws {
    let a = AssertionsParser.parse(try fixture("pmset-assertions.txt"))
    #expect(a.count == 4)
    #expect(a.contains { $0.processName == "powerd" && $0.type == "PreventUserIdleSystemSleep" })
    #expect(a.first { $0.pid == 44846 }?.onBehalfOf == "npm")
    #expect(a.first { $0.pid == 60450 }?.onBehalfOf == nil)
}
