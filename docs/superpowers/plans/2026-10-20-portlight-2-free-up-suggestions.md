# Portlight 2: Free-up Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (owner chose inline execution). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The panel's new **Clean Up** tile suggests which processes to quit to free ports, ranked, each with a plain reason and its own Quit button, plus "Free all". "Is port free?" shows the blocking process's reason and a Quit button.

**Architecture:** Two pure, clock-injected pieces in `PortlightCore`. `ActivityTracker` remembers when each process was last active (it had a connection or used CPU). `SuggestionEngine` turns entries + activity + stay-awake holds into ranked `Suggestion`s. The scanner additionally reports established connections per (pid, local port). The inspector adds CPU time and session-leader checks. The app store samples on every refresh, and the panel quits inline (no modal alerts from the menu bar).

**Tech Stack:** as Plan 1 (Swift 6.3, SwiftUI, libproc, Swift Testing).

**Spec:** `docs/superpowers/specs/2026-10-20-portlight-design.md`: "Free-up suggestions" and "Idle/zombie" under Behaviour rules.

## Global Constraints

- Everything in Plan 1's Global Constraints still holds (macOS 14+, CLT-only build, no network, sanitised fixtures, `scripts/test.sh`).
- Reasons, strongest first (spec): **Duplicate** > **Orphaned** > **Exposed and idle** > **Idle**.
- Idle = zero established connections and CPU growth under 1 s per hour (`cpuIdleRate = 1/3600`) since last active, for at least `idleThreshold = 2 h`.
- Never suggested (spec): any process with a Stay Awake hold; anything `QuitPolicy.canQuit` refuses; databases (`postgres`, `mongod`, `redis-server`, `mysqld`); anything active in the last 5 minutes (`recentWindow = 300 s`).
- Idle time is measured from when Portlight first saw the process (it has no earlier history). The UI says "idle 2 h+" style durations, never claiming more than it observed.
- Copy (owner may change): Duplicate: "Duplicate. <project> is already running on :<port>". Orphaned: "Orphaned. The terminal that started it has closed". Exposed: "Open to your network and idle <dur>". Idle: "Idle <dur>, no connections". Port check with no reason: "In use now".
- Quitting from the menu-bar panel uses inline two-step buttons (Quit → Confirm), never `NSAlert`. If the process ignores SIGTERM, the row offers **Force Quit** inline.

## Review Focus

- GUI apps and `brew services` agents have parent PID 1 but are not orphans. Orphaned = parent PID 1 **and** not a session leader (`getsid(pid) != pid`) **and** not inside an `.app` bundle. → Task 4 test `appBundleIsNotOrphan`, Task 2 test `sessionLeaderFlag`.
- The same process listening on several ports (`node` on 3000 + 9229) must be suggested **once**, listing all its ports. → Task 4 test `oneSuggestionPerProcess`.
- A duplicate pair must suggest only the **newer** process, never both. → Task 4 test `duplicateSuggestsNewerOnly`.
- A process seen for the first time has no history. It must not be called idle until the threshold has passed since first sight. → Task 3 test `firstSightIsActive`.
- A suggestion whose process has already exited (quit elsewhere) must disappear on the next refresh, and "Free all" must skip it without error. → Task 3 test `forgetsGoneProcesses`, Task 5 `freeAll` uses `TerminateResult.exited` as success.

---

### Task 1: Established connections in the scan + CI on macOS 14

**Files:**
- Modify: `Sources/PortlightCore/Sockets/NetstatParser.swift`, `Sources/PortlightCore/Sockets/PortScanner.swift`, `Sources/Portlight/Model/PortStore.swift`, `Tests/PortlightTests/PortStoreTests.swift`, `Tests/PortlightCoreTests/FreePortTests.swift`
- Create: `Tests/PortlightCoreTests/ConnectionCountTests.swift`

**Interfaces:**
- Produces:
  - `public struct ScanResult: Sendable { public let listening: [ListeningSocket]; public let connections: [ConnectionKey: Int] }`
  - `public struct ConnectionKey: Sendable, Hashable { public let pid: Int32; public let localPort: UInt16 }`
  - `NetstatParser.connections(_ output: String) -> [ConnectionKey: Int]`: counts TCP `ESTABLISHED` rows by (pid, local port), using the same header layout.
  - `PortScanning.scan() throws -> ScanResult` (replaces `[ListeningSocket]`).

- [ ] **Step 1: Failing test**

```swift
@Test(arguments: ["netstat-tcp.txt", "netstat-tcp-macos15.txt"])
func countsEstablished(_ file: String) throws {
    let c = NetstatParser.connections(try fixture(file))
    #expect(c.values.reduce(0, +) == 1)
    #expect(c[ConnectionKey(pid: file == "netstat-tcp.txt" ? 86926 : 2001, localPort: 57092)] == 1)
}
```

- [ ] **Step 2:** Run `scripts/test.sh --filter countsEstablished`. Expected: FAIL (not defined).
- [ ] **Step 3:** Implement. Share the token/layout logic with `parse`, then change `NetstatScanner.scan()` to return `ScanResult` (one TCP netstat call feeds both). Update `PortStore.refresh` and the test fakes to the new type. `scannerSeesOwnListener` reads `.listening`.
- [ ] **Step 4:** Run `scripts/test.sh`. Expected: all pass.
- [ ] **Step 5:** Commit `feat(core): count established connections per port`. Push, including the already committed macOS 14 CI matrix. Both CI jobs must pass.

### Task 2: CPU time and session-leader facts

**Files:**
- Modify: `Sources/PortlightCore/Process/ProcessDetails.swift`, `Sources/PortlightCore/Process/ProcessInspector.swift`, `Tests/PortlightCoreTests/TestSupport.swift`, `Tests/PortlightTests/PortStoreTests.swift`
- Test: `Tests/PortlightCoreTests/ProcessInspectorTests.swift`

**Interfaces:**
- Produces:
  - `ProcessDetails.isSessionLeader: Bool` (`getsid(pid) == pid`; false if `getsid` fails).
  - `ProcessInspecting.cpuTime(pid: Int32) -> TimeInterval?`: total user + system seconds from `PROC_PIDTASKINFO` (`pti_total_user + pti_total_system`, in ns → s). nil when not permitted.
  - `details(...)` test helper gains `sessionLeader: Bool = false`.

- [ ] **Step 1: Failing tests**

```swift
@Test func cpuTimeGrowsWhileBusy() throws {
    let i = ProcessInspector()
    let t0 = try #require(i.cpuTime(pid: getpid()))
    var x = 0.0; for n in 0..<3_000_000 { x += sin(Double(n)) }
    #expect(x != 0.123)
    #expect(try #require(i.cpuTime(pid: getpid())) > t0)
}

@Test func sessionLeaderFlag() throws {
    let p = try spawn("/usr/bin/python3", ["-c", "import os,time; os.setsid(); time.sleep(5)"])
    defer { p.terminate() }
    Thread.sleep(forTimeInterval: 0.3)
    #expect(try #require(ProcessInspector().details(pid: p.processIdentifier)).isSessionLeader == true)
    #expect(try #require(ProcessInspector().details(pid: getpid())).isSessionLeader == false)
}
```

- [ ] **Step 2:** Run `scripts/test.sh --filter "cpuTime|sessionLeader"`. Expected: FAIL.
- [ ] **Step 3:** Implement as specified.
- [ ] **Step 4:** Run `scripts/test.sh`. Expected: all pass.
- [ ] **Step 5:** Commit `feat(core): read CPU time and session leadership`.

### Task 3: ActivityTracker

**Files:**
- Create: `Sources/PortlightCore/Suggestions/ActivityTracker.swift`, `Tests/PortlightCoreTests/ActivityTrackerTests.swift`

**Interfaces:**
- Consumes: `ProcessIdentity`, `ConnectionKey`.
- Produces:
  - `public struct ActivitySample: Sendable { public let identity: ProcessIdentity; public let ports: [UInt16]; public let cpuTime: TimeInterval? }`
  - `public struct ActivityTracker: Sendable { public init(); public mutating func record(_ samples: [ActivitySample], connections: [ConnectionKey: Int], now: Date); public func lastActive(_ identity: ProcessIdentity) -> Date? }`

Rules: first sight → `lastActive = now`. On later samples, if any of its ports has a connection > 0, or CPU grew by more than `cpuIdleRate × elapsed` since the previous sample, then `lastActive = now`. Identities missing from a `record` call are forgotten.

- [ ] **Step 1: Failing tests**: `firstSightIsActive` (lastActive == t0), `connectionKeepsActive`, `cpuGrowthKeepsActive` (cpu +10 s over 1 h → active), `smallCpuTickIsIdle` (cpu +0.5 s over 1 h → lastActive stays t0), `forgetsGoneProcesses` (absent in second record → nil), `pidReuseIsNewProcess` (same pid, new startTime → lastActive = new now).
- [ ] **Step 2:** Run `scripts/test.sh --filter ActivityTracker`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `scripts/test.sh`. Expected: all pass.
- [ ] **Step 5:** Commit `feat(core): track when processes were last active`.

### Task 4: SuggestionEngine

**Files:**
- Create: `Sources/PortlightCore/Suggestions/Suggestion.swift`, `Sources/PortlightCore/Suggestions/SuggestionEngine.swift`, `Tests/PortlightCoreTests/SuggestionEngineTests.swift`

**Interfaces:**
- Consumes: `PortEntry`, `ProcessIdentity`, `QuitPolicy`, `ProjectResolver.knownServers`.
- Produces:
  - `public enum SuggestionReason: Sendable, Equatable { case duplicate(project: String, port: UInt16); case orphaned; case exposedIdle(TimeInterval); case idle(TimeInterval) }` with `public var text: String` (copy from Global Constraints; durations via `DateComponentsFormatter` abbreviated hours/minutes).
  - `public struct Suggestion: Sendable, Identifiable, Equatable { public var id: ProcessIdentity { identity }; public let identity: ProcessIdentity; public let label: String; public let project: String?; public let ports: [UInt16]; public let reason: SuggestionReason }`
  - `public enum SuggestionEngine { public static let idleThreshold: TimeInterval = 7200; public static let recentWindow: TimeInterval = 300; public static func suggest(entries: [PortEntry], lastActive: (ProcessIdentity) -> Date?, held: Set<ProcessIdentity>, now: Date) -> [Suggestion] }`. The result is sorted by reason strength, then longest idle first.

Rules: group entries by `details.identity` (skip entries without details). Exclusions as in Global Constraints. Duplicate: another eligible-or-not process with the same `project.name` (non-nil) and the same `project.label`, the same uid, and an earlier `startTime` → suggest this (newer) one, with the older one's lowest port. Orphaned: `parentPid == 1 && !isSessionLeader && !(executablePath contains ".app/")`, and not active within `recentWindow`. Exposed idle: any port `.network` and idle ≥ `idleThreshold`. Idle: idle ≥ `idleThreshold`. Each process takes only its strongest reason.

- [ ] **Step 1: Failing tests**: `duplicateSuggestsNewerOnly`, `oneSuggestionPerProcess`, `appBundleIsNotOrphan`, `sessionLeaderIsNotOrphan`, `orphanSuggested`, `exposedOutranksIdle`, `idleUnderThresholdNotSuggested` (1 h 59 m), `recentActivityExcluded` (duplicate active 1 min ago → none), `heldExcluded`, `databaseExcluded` (label `postgres`), `otherUserExcluded` (uid 0), `reasonText` (exact copy for each case, e.g. `.idle(9 * 3600).text == "Idle 9h, no connections"`).
- [ ] **Step 2:** Run `scripts/test.sh --filter SuggestionEngine`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `scripts/test.sh`. Expected: all pass.
- [ ] **Step 5:** Commit `feat(core): suggest which processes to quit, with reasons`.

### Task 5: Store integration, Clean Up tile, port-check reasons, inline quit

**Files:**
- Create: `Sources/Portlight/MenuBar/CleanUpTile.swift`, `Sources/Portlight/MenuBar/InlineQuitButton.swift`
- Modify: `Sources/Portlight/Model/PortStore.swift`, `Sources/Portlight/MenuBar/MenuPanel.swift`, `Sources/Portlight/MenuBar/PortCheckTile.swift`, `Tests/PortlightTests/PortStoreTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: `PortStore.suggestions: [Suggestion]` (recomputed on every applied scan); `PortStore.suggestion(for pid: Int32) -> Suggestion?`; `PortStore.quit(_ identity: ProcessIdentity) async -> TerminateResult`; `PortStore.forceQuit(_ identity: ProcessIdentity) async -> TerminateResult` (runs `forceKill` off the main actor); `PortStore.freeAll() async -> Int` (count freed).

- [ ] **Step 1: Failing test** `suggestionsFollowScans`: a scripted scanner and a fake inspector seed two identical-label processes in one project. After `refresh()`, `store.suggestions.count == 1`, using an injected `now` clock (`PortStore.init(..., clock: @escaping () -> Date = Date.init)`) advanced past `recentWindow`.
- [ ] **Step 2:** Run `scripts/test.sh --filter suggestionsFollowScans`. Expected: FAIL.
- [ ] **Step 3:** Implement the store pieces. On each applied scan, build `ActivitySample`s (with `inspector.cpuTime`), call `tracker.record`, then `SuggestionEngine.suggest`.
- [ ] **Step 4:** Implement the UI:
  - **Clean Up tile**, placed after Listening: shows "Clean Up" with "Nothing to free" or "N suggestions". The top 3 rows show `label · :ports`, a caption with the reason text (orange for exposed), and an `InlineQuitButton`. "Free all N" is two-step and shows "Freed N" for 3 s.
  - **InlineQuitButton**: Quit → Confirm (reverts after 3 s) → spinner. On `.stillRunning` it shows "Force Quit"; on `.failed` it shows "Couldn't quit" in red.
  - **PortCheckTile**: when the owner is quittable, add a second line with the suggestion's reason text (or "In use now") and an `InlineQuitButton`.
- [ ] **Step 5:** Run `swift build && scripts/test.sh`. Expected: build complete with no warnings, and all tests pass.
- [ ] **Step 6:** Commit `feat(app): Clean Up suggestions in the menu bar`. Run `scripts/make-app.sh`, relaunch, push, and confirm CI is green on both OS versions.
