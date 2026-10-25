import Foundation
import Testing
@testable import PortlightCore

private let now = Date(timeIntervalSince1970: 2_000_000)
private let hour: TimeInterval = 3600

private func entry(
    _ port: UInt16, pid: Int32, label: String = "next dev", project: String? = "web",
    reach: Reach = .local, start: UInt64 = 1, parent: Int32 = 500, groupLeader: Bool = false,
    path: String = "/opt/homebrew/bin/node", uid: uid_t = getuid()
) -> PortEntry {
    PortEntry(
        port: port, proto: .tcp, reach: reach, pid: pid, processName: "node",
        project: ProjectInfo(name: project, label: label),
        details: details(pid: pid, path: path, uid: uid, parent: parent, groupLeader: groupLeader, start: start)
    )
}

/// Every process was last active `idle` ago unless overridden.
private func suggest(
    _ entries: [PortEntry], idle: TimeInterval = 3 * hour, active: [Int32: TimeInterval] = [:],
    held: Set<ProcessIdentity> = []
) -> [Suggestion] {
    SuggestionEngine.suggest(
        entries: entries,
        lastActive: { now - (active[$0.pid] ?? idle) },
        held: held, now: now
    )
}

@Test func duplicateSuggestsNewerOnly() {
    let s = suggest([entry(3000, pid: 101, start: 100), entry(3001, pid: 102, start: 200)], idle: 10 * 60)
    #expect(s.map(\.identity.pid) == [102])
    #expect(s.first?.reason == .duplicate(project: "web", port: 3000))
}

@Test func differentLabelsAreNotDuplicates() {
    let s = suggest([entry(3000, pid: 101, start: 100), entry(6006, pid: 102, label: "storybook", start: 200)], idle: 10 * 60)
    #expect(s.isEmpty)
}

@Test func oneSuggestionPerProcess() {
    let s = suggest([entry(3000, pid: 101), entry(9229, pid: 101)])
    #expect(s.count == 1)
    #expect(s.first?.ports == [3000, 9229])
}

@Test func orphanSuggested() {
    let s = suggest([entry(3000, pid: 101, parent: 1)], idle: 31 * 60)
    #expect(s.first?.reason == .orphaned)
}

@Test func appBundleIsNotOrphan() {
    let s = suggest([entry(7000, pid: 101, parent: 1, path: "/Applications/Spotify.app/Contents/MacOS/Spotify")], idle: 10 * 60)
    #expect(s.isEmpty)
}

@Test func groupLeaderIsNotOrphan() {
    let s = suggest([entry(11434, pid: 101, parent: 1, groupLeader: true)], idle: 10 * 60)
    #expect(s.isEmpty)
}

@Test func exposedOutranksIdle() throws {
    let s = suggest([entry(6006, pid: 101, label: "storybook"), entry(8080, pid: 102, label: "python http.server", reach: .network)])
    try #require(s.count == 2)
    #expect(s.map(\.identity.pid) == [102, 101])
    #expect(s[0].reason == .exposedIdle(3 * hour))
    #expect(s[1].reason == .idle(3 * hour))
}

@Test func longestIdleFirstWithinReason() throws {
    let s = suggest(
        [entry(6006, pid: 101, label: "storybook"), entry(5173, pid: 102, label: "vite")],
        active: [101: 3 * hour, 102: 9 * hour])
    try #require(s.count == 2)
    #expect(s.map(\.identity.pid) == [102, 101])
}

@Test func idleUnderThresholdNotSuggested() {
    #expect(suggest([entry(6006, pid: 101, label: "storybook")], idle: 2 * hour - 60).isEmpty)
    #expect(suggest([entry(6006, pid: 101, label: "storybook")], idle: 2 * hour).count == 1)
}

@Test func recentActivityExcluded() {
    let s = suggest([entry(3000, pid: 101, start: 100), entry(3001, pid: 102, start: 200)], active: [102: 60])
    #expect(!s.contains { $0.identity.pid == 102 })
}

@Test func heldExcluded() {
    let e = entry(6006, pid: 101, label: "storybook")
    #expect(suggest([e], held: [e.details!.identity]).isEmpty)
}

@Test func databaseExcluded() {
    #expect(suggest([entry(5432, pid: 101, label: "postgres", path: "/opt/homebrew/bin/postgres")]).isEmpty)
}

@Test func otherUserExcluded() {
    #expect(suggest([entry(6006, pid: 101, label: "storybook", uid: 0)]).isEmpty)
}

@Test func entriesWithoutDetailsIgnored() {
    let e = PortEntry(port: 22, proto: .tcp, reach: .network, pid: 101, processName: "sshd",
                      project: ProjectInfo(name: nil, label: "sshd"), details: nil)
    #expect(suggest([e]).isEmpty)
}

@Test func reasonText() {
    #expect(SuggestionReason.duplicate(project: "my-app", port: 3000).text
        == "Duplicate. my-app is already running on :3000")
    #expect(SuggestionReason.orphaned.text == "Orphaned. The terminal that started it has closed")
    #expect(SuggestionReason.exposedIdle(9 * hour).text == "Open to your network and idle 9h")
    #expect(SuggestionReason.idle(9 * hour).text == "Idle 9h, no connections")
    #expect(SuggestionReason.idle(2.5 * hour).text == "Idle 2h 30m, no connections")
}

@Test func olderTwinNeverSuggestedAlongsideNewer() {
    // Older twin idle 3 h, newer idle 10 min: suggesting both would kill the project's only servers.
    let s = suggest([entry(3000, pid: 101, start: 100), entry(3001, pid: 102, start: 200)], active: [101: 3 * hour, 102: 10.0 * 60])
    #expect(s.map(\.identity.pid) == [102])
}

@Test func unrecognisedLabelsAreNotDuplicates() {
    // `node api.js` and `node mock.js` both fall back to the label "node".
    let s = suggest([entry(4000, pid: 101, label: "node", start: 100), entry(4001, pid: 102, label: "node", start: 200)], idle: 10 * 60)
    #expect(s.isEmpty)
}

@Test func orphanNeedsProjectAndHalfHourIdle() {
    #expect(suggest([entry(2019, pid: 101, label: "caddy", project: nil, parent: 1)], idle: 3 * hour).first?.reason != .orphaned)
    #expect(suggest([entry(3000, pid: 101, parent: 1)], idle: 29 * 60).isEmpty)
}
