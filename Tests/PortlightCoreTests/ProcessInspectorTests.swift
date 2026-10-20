import Foundation
import Testing
@testable import PortlightCore

@Test func inspectsSelf() throws {
    let d = try #require(ProcessInspector().details(pid: getpid()))
    #expect(d.uid == getuid())
    #expect(d.workingDirectory == FileManager.default.currentDirectoryPath)
    #expect(d.arguments.isEmpty == false)
    #expect(d.executablePath?.isEmpty == false)
}

@Test func deadPidReturnsNil() throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try p.run()
    p.waitUntilExit()
    #expect(ProcessInspector().details(pid: p.processIdentifier) == nil)
}

@Test func identityStableForSameProcess() throws {
    let i = ProcessInspector()
    let id = try #require(i.identity(pid: getpid()))
    #expect(id == i.identity(pid: getpid()))
    #expect(id.startTime > 0)
}

@Test func readsChildArguments() async throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sleep")
    p.arguments = ["5"]
    try p.run()
    defer { p.terminate() }
    try await Task.sleep(for: .milliseconds(100))
    let d = try #require(ProcessInspector().details(pid: p.processIdentifier))
    #expect(d.arguments == ["/bin/sleep", "5"])
    #expect(d.parentPid == getpid())
}

@Test func namesProcessesOfOtherUsers() {
    #expect(ProcessInspector().processName(pid: 1) == "launchd")
    #expect(ProcessInspector().processName(pid: getpid())?.isEmpty == false)
}
