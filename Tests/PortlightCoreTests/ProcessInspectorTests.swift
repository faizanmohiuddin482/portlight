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

@Test func cpuTimeGrowsWhileBusy() throws {
    let i = ProcessInspector()
    let t0 = try #require(i.cpuTime(pid: getpid()))
    var x = 0.0
    for n in 0..<3_000_000 { x += sin(Double(n)) }
    #expect(x != 0.123)
    #expect(try #require(i.cpuTime(pid: getpid())) > t0)
}

@Test func groupLeaderFlag() throws {
    let p = try spawn("/usr/bin/perl", ["-MPOSIX", "-e", "POSIX::setsid(); sleep 5"])
    defer { p.terminate() }
    Thread.sleep(forTimeInterval: 0.5)
    #expect(try #require(ProcessInspector().details(pid: p.processIdentifier)).isGroupLeader == true)
    // Foundation puts each child in its own group, so use a grandchild: it stays
    // in its parent's group, like `node` under `npm run dev`.
    let parent = Process()
    parent.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    parent.arguments = ["-e", #"$| = 1; my $c = fork; if (!$c) { sleep 5; exit } print "$c\n"; sleep 5"#]
    let out = Pipe()
    parent.standardOutput = out
    try parent.run()
    defer { parent.terminate() }
    let line = String(decoding: out.fileHandleForReading.availableData, as: UTF8.self)
    let grandchild = try #require(Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)))
    defer { kill(grandchild, SIGTERM) }
    #expect(try #require(ProcessInspector().details(pid: grandchild)).isGroupLeader == false)
}
