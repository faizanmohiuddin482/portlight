import Foundation
import Testing
@testable import PortlightCore

@MainActor @Test func holdsAssertionWhileActive() {
    let b = FakeBackend(); let m = StayAwakeManager(backend: b)
    m.start(id1, name: "api", duration: nil)
    #expect(m.isActive)
    #expect(b.live.count == 1)
}

@MainActor @Test func releasesOnExit() {
    let b = FakeBackend(); let m = StayAwakeManager(backend: b)
    m.start(id1, name: "api", duration: nil)
    m.tick(now: .now, isAlive: { _ in false })
    #expect(m.holds.isEmpty)
    #expect(b.live.isEmpty)
}

@MainActor @Test func releasesOnDeadline() {
    let b = FakeBackend(); let m = StayAwakeManager(backend: b); let t0 = Date()
    m.start(id1, name: "x", duration: 3600, now: t0)
    m.tick(now: t0.addingTimeInterval(3599), isAlive: { _ in true })
    #expect(m.isActive)
    m.tick(now: t0.addingTimeInterval(3600), isAlive: { _ in true })
    #expect(!m.isActive)
    #expect(b.live.isEmpty)
}

@MainActor @Test func releasesWhenPidReused() {
    let b = FakeBackend(); let m = StayAwakeManager(backend: b)
    m.start(ProcessIdentity(pid: 42, startTime: 1), name: "x", duration: nil)
    m.tick(now: .now, isAlive: { $0 == ProcessIdentity(pid: 42, startTime: 2) })
    #expect(m.holds.isEmpty)
}

@MainActor @Test func multipleHoldsAndStopAll() {
    let b = FakeBackend(); let m = StayAwakeManager(backend: b)
    m.start(id1, name: "a", duration: nil)
    m.start(id2, name: "b", duration: nil)
    #expect(b.live.count == 2)
    m.start(id1, name: "a", duration: 60)
    #expect(b.live.count == 2)
    #expect(m.holds.count == 2)
    m.stopAll()
    #expect(b.live.isEmpty)
    #expect(m.holds.isEmpty)
}

@MainActor @Test func stopOne() throws {
    let b = FakeBackend(); let m = StayAwakeManager(backend: b)
    m.start(id1, name: "a", duration: nil)
    m.start(id2, name: "b", duration: nil)
    m.stop(try #require(m.holds.first { $0.identity == id1 }).id)
    #expect(m.holds.map(\.identity) == [id2])
    #expect(b.live.count == 1)
}

@MainActor @Test func realAssertionShowsInPmset() throws {
    let m = StayAwakeManager()
    m.start(id1, name: "portlight-test", duration: nil)
    defer { m.stopAll() }
    #expect(currentSleepAssertions().contains { $0.name == "Portlight: keeping awake for portlight-test" })
}
