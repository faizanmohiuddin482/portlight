import Foundation
import Testing
@testable import PortlightCore

@Test func quitPolicy() {
    #expect(QuitPolicy.canQuit(details(path: "/opt/homebrew/bin/node", uid: getuid())) == true)
    #expect(QuitPolicy.canQuit(details(path: "/opt/homebrew/bin/node", uid: 0)) == false)
    #expect(QuitPolicy.canQuit(details(path: "/usr/libexec/rapportd", uid: getuid())) == false)
    #expect(QuitPolicy.canQuit(details(path: "/usr/sbin/sshd", uid: getuid())) == false)
    #expect(QuitPolicy.canQuit(details(path: "/System/Library/x", uid: getuid())) == false)
    #expect(QuitPolicy.canQuit(details(pid: getpid(), path: "/x/Portlight", uid: getuid())) == false)
    #expect(QuitPolicy.canQuit(nil) == false)
}

@Test func terminatesSleep() async throws {
    let p = try spawn("/bin/sleep", ["30"])
    let id = try #require(ProcessInspector().identity(pid: p.processIdentifier))
    #expect(await ProcessController().terminate(id) == .exited)
}

@Test func reportsSurvivorOfSigterm() async throws {
    let p = try spawn("/bin/sh", ["-c", "trap '' TERM; while :; do sleep 0.1; done"])
    try await Task.sleep(for: .milliseconds(200))
    let id = try #require(ProcessInspector().identity(pid: p.processIdentifier))
    let c = ProcessController()
    #expect(await c.terminate(id, grace: .milliseconds(500)) == .stillRunning)
    #expect(c.forceKill(id) == .exited)
}

@Test func refusesRecycledPid() async {
    let stale = ProcessIdentity(pid: getpid(), startTime: 1)
    #expect(await ProcessController().terminate(stale) == .exited)
    #expect(ProcessController().isAlive(stale) == false)
}
