# Portlight 1: Core Engine + Menu Bar MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A runnable `Portlight.app` that lives in the menu bar, lists every listening port with process and project names, checks whether a port is free, quits processes safely, and keeps the Mac awake for a chosen process. The repo is public on GitHub with CI.

**Architecture:** A SwiftPM package with a UI-free library `PortlightCore` (scanning, process inspection, project naming, free-port logic, quitting, stay-awake) and a SwiftUI executable `Portlight` (store + views). `netstat -anv` is the port source because it lists every user's sockets with `process:pid` and needs no root. libproc fills in details for the PIDs we are allowed to inspect. A script assembles and ad-hoc signs the `.app`.

**Tech Stack:** Swift 6.3, SwiftUI + AppKit, `MenuBarExtra(.window)`, Darwin libproc/sysctl, IOKit power assertions, Swift Testing, GitHub Actions (macOS runner).

**Spec:** `docs/superpowers/specs/2026-10-20-portlight-design.md`

**Later plans (not this one):** 2 = full window views (By Project, On Network, Stay Awake, History), detail pane, idle/zombie detection + Clean Up tile, monthly share card. 3 = Lid Closed (root watcher, safeguards, crash recovery, notification). 4 = ship: icon, README + demo GIF, Sparkle, release workflow, Homebrew tap, signing/notarization.

## Global Constraints

- macOS 14 Sonoma or newer; universal binary (arm64 + x86_64).
- Swift 6 + SwiftUI (AppKit where SwiftUI falls short). No Electron, no web views, no third-party dependencies in this plan.
- Must build with the Command Line Tools only (no Xcode). Tests run through `scripts/test.sh`, which adds the CLT `Testing.framework` paths; on CI (Xcode present) plain `swift test` works.
- No network calls. No root to list ports. No data leaves the machine.
- Bundle ID `io.github.faizanmohiuddin482.portlight`; app is `LSUIElement` (menu bar only, no Dock icon).
- Follow the Apple HIG: SF Pro, SF Symbols, system colours (accent blue = awake, orange = on network, green = healthy), materials, light + dark mode.
- Quit rules (spec): SIGTERM first, offer Force Quit (SIGKILL) if still alive after 3 s; confirm the first time with "Don't ask again"; no quit button for root/other users' processes or anything under `/System`, `/usr/libexec`, `/usr/sbin`.
- Stay Awake (spec): IOPM `PreventUserIdleSystemSleep` (display may sleep), tied to a process; released on process exit, timer end (options: until it exits / 1 h / 2 h / 4 h / custom), or app quit; several holds at once.
- Refresh (spec): every 2 s while panel/window visible, every 15 s in the background.
- MIT licence. Repo `faizanmohiuddin482/portlight`, public.
- Test fixtures must be sanitised: no real hostnames, private IPs other than `192.168.1.10`, or personal process names.

## Review Focus

- The same port on IPv4 and IPv6 (`tcp46`, or separate `tcp4` + `tcp6` lines) must show as **one** row, marked network if either is network. → Task 4 test `mergesDualStack`.
- A process that exits between the scan and the inspection must still show (name from netstat) without crashing. → Task 3 test `deadPidReturnsNil`, Task 4 test `entryWithoutDetails`.
- PID reuse: if a kept-awake process dies and its PID is recycled, the hold must still release. → Task 6 test `releasesWhenPidReused` (identity = pid + start time).
- Process names with spaces or truncation in netstat (`Google Chrome He:86926`) must parse. → Task 2 test `parsesNamesWithSpaces`.
- A process that ignores SIGTERM must be reported still alive so the UI offers Force Quit. → Task 5 test `reportsSurvivorOfSigterm`.

---

### Task 1: Package scaffold, test script, CI, public repo

**Files:**
- Create: `Package.swift`, `Sources/PortlightCore/PortlightCore.swift` (empty namespace file), `Sources/Portlight/PortlightApp.swift`, `Tests/PortlightCoreTests/SmokeTests.swift`, `scripts/test.sh`, `.github/workflows/ci.yml`, `.gitignore`, `LICENSE` (MIT, "Faizan Mohiuddin"), `README.md` (one-line pitch + "work in progress").

**Interfaces:**
- Produces: targets `PortlightCore` (library), `Portlight` (executable), `PortlightCoreTests`; `scripts/test.sh [swift test args]`.

- [ ] **Step 1:** `git init` in `~/src/portlight`, branch `main`. `.gitignore`: `.build/`, `build/`, `.swiftpm/`, `.superpowers/`, `*.xcodeproj/xcuserdata`, `.DS_Store`.
- [ ] **Step 2:** `Package.swift`: `swift-tools-version:6.0`, `platforms: [.macOS(.v14)]`, the three targets above.
- [ ] **Step 3:** `PortlightApp.swift`: `@main struct PortlightApp: App` with a `MenuBarExtra("Portlight", systemImage: "light.beacon.max")` showing `Text("Portlight")`, `.menuBarExtraStyle(.window)`.
- [ ] **Step 4:** Smoke test:

```swift
import Testing
@testable import PortlightCore
@Test func packageBuilds() { #expect(true) }
```

- [ ] **Step 5:** `scripts/test.sh`: if `xcode-select -p` points at `/Library/Developer/CommandLineTools`, run `swift test` with `-Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L` where `F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks` and `L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib`; otherwise plain `swift test`. Pass through `"$@"`. `set -euo pipefail`.
- [ ] **Step 6:** Run `scripts/test.sh`. Expected: `✔ Test run with 1 test … passed`.
- [ ] **Step 7:** `ci.yml`: on push to `main` and on PRs, `runs-on: macos-15`, steps: checkout, `swift build`, `swift test`.
- [ ] **Step 8:** Commit `chore: scaffold Portlight package`. Create the public repo `gh repo create faizanmohiuddin482/portlight --public --source . --push --description "Who's on port 3000? A native macOS menu bar app for your ports — and for keeping your Mac awake while they work."`. Verify `gh run list -L1` goes green.

### Task 2: netstat parser

**Files:**
- Create: `Sources/PortlightCore/Sockets/ListeningSocket.swift`, `Sources/PortlightCore/Sockets/NetstatParser.swift`, `Tests/PortlightCoreTests/Fixtures/netstat-tcp.txt`, `Tests/PortlightCoreTests/Fixtures/netstat-udp.txt`, `Tests/PortlightCoreTests/NetstatParserTests.swift`
- Modify: `Package.swift` (test target `resources: [.copy("Fixtures")]`)

**Interfaces:**
- Produces:
  - `public enum TransportProtocol: String, Sendable { case tcp, udp }`
  - `public enum Reach: Sendable { case local, network; public static func of(address: String) -> Reach }`
  - `public struct ListeningSocket: Sendable, Hashable { public let proto: TransportProtocol; public let address: String; public let port: UInt16; public let pid: Int32; public let processName: String; public var reach: Reach { get } }`
  - `public enum NetstatParser { public static func parse(_ output: String, proto: TransportProtocol) -> [ListeningSocket] }`

Fixture `netstat-tcp.txt` = the real header line plus these sanitised lines (one ESTABLISHED that must be ignored):

```
tcp4       0      0  192.168.1.10.57092     20.0.0.1.443           ESTABLISHED         9118        30517  131072  132432 Google Chrome He:86926  00102 00000008 0000000001519a44 00000080 04000900      2      0 000000
tcp46      0      0  *.3000                 *.*                    LISTEN                 0            0  131072  131072             node:51541  00100 00000106 00000000015036b4 00000001 00000800      1      0 000000
tcp4       0      0  127.0.0.1.8000         *.*                    LISTEN                 0            0  131072  131072           Python:50887  00100 00000106 0000000001501c96 00000000 00000800      1      0 000000
tcp6       0      0  ::1.5432               *.*                    LISTEN                 0            0  131072  131072           postgres:701  00100 00000106 0000000001501c97 00000000 00000800      1      0 000000
tcp4       0      0  *.7000                 *.*                    LISTEN                 0            0  131072  131072 Google Chrome He:86926  00100 00000106 0000000001501c98 00000000 00000800      1      0 000000
```

Fixture `netstat-udp.txt` = header plus `udp4 … *.3722 *.* … rapportd:630 …` and `udp6 … *.3722 …` (as captured during planning) plus `udp4 0 0 127.0.0.1.53 *.* 0 0 786896 9216 dnsmasq:900 00100 …`.

- [ ] **Step 1: Write failing tests**

```swift
@Test func parsesListenersOnly() throws {
    let s = NetstatParser.parse(try fixture("netstat-tcp.txt"), proto: .tcp)
    #expect(s.map(\.port) == [3000, 8000, 5432, 7000])
}
@Test func parsesNamesWithSpaces() throws {
    let s = NetstatParser.parse(try fixture("netstat-tcp.txt"), proto: .tcp)
    #expect(s.last?.processName == "Google Chrome He")
    #expect(s.last?.pid == 86926)
}
@Test func reachFromAddress() {
    #expect(Reach.of(address: "127.0.0.1") == .local)
    #expect(Reach.of(address: "::1") == .local)
    #expect(Reach.of(address: "*") == .network)
    #expect(Reach.of(address: "192.168.1.10") == .network)
}
@Test func parsesUdpBoundSockets() throws {
    let s = NetstatParser.parse(try fixture("netstat-udp.txt"), proto: .udp)
    #expect(s.count == 3)
    #expect(s.first { $0.port == 53 }?.reach == .local)
}
@Test func ignoresGarbage() { #expect(NetstatParser.parse("nonsense\n\n", proto: .tcp).isEmpty) }
```

(`fixture(_:)` helper reads from `Bundle.module`.)

- [ ] **Step 2:** Run `scripts/test.sh --filter NetstatParser`. Expected: FAIL (types not defined).
- [ ] **Step 3: Implement.** Per line: split the local address at its **last** `.` into address + port (`*.3000` → `*`, `3000`; `::1.5432` → `::1`, `5432`). Find `process:pid` with the regex `\s(\S.*?):(\d+)\s+[0-9a-f]{5}\s`, taken after the shiwat column. TCP keeps only lines whose state column is `LISTEN`. UDP keeps lines whose foreign address is `*.*`. `Reach.local` for `127.*`, `::1`, `localhost`, `fe80::1%lo0`; everything else, including `*`, is `.network`.
- [ ] **Step 4:** Run `scripts/test.sh --filter NetstatParser`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(core): parse netstat listeners`.

### Task 3: Process inspector (libproc)

**Files:**
- Create: `Sources/PortlightCore/Process/ProcessDetails.swift`, `Sources/PortlightCore/Process/ProcessInspector.swift`, `Tests/PortlightCoreTests/ProcessInspectorTests.swift`

**Interfaces:**
- Produces:
  - `public struct ProcessIdentity: Sendable, Hashable { public let pid: Int32; public let startTime: UInt64 }` (start = `pbi_start_tvsec * 1_000_000 + pbi_start_tvusec`)
  - `public struct ProcessDetails: Sendable, Equatable { public let identity: ProcessIdentity; public let executablePath: String?; public let arguments: [String]; public let workingDirectory: String?; public let uid: uid_t; public let parentPid: Int32 }`
  - `public protocol ProcessInspecting: Sendable { func details(pid: Int32) -> ProcessDetails?; func identity(pid: Int32) -> ProcessIdentity? }`
  - `public struct ProcessInspector: ProcessInspecting { public init() }`

- [ ] **Step 1: Failing tests**

```swift
@Test func inspectsSelf() throws {
    let d = try #require(ProcessInspector().details(pid: getpid()))
    #expect(d.uid == getuid())
    #expect(d.workingDirectory == FileManager.default.currentDirectoryPath)
    #expect(d.arguments.isEmpty == false)
}
@Test func deadPidReturnsNil() throws {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try p.run(); p.waitUntilExit()
    #expect(ProcessInspector().details(pid: p.processIdentifier) == nil)
}
@Test func identityStableForSameProcess() {
    let i = ProcessInspector()
    #expect(i.identity(pid: getpid()) == i.identity(pid: getpid()))
}
```

- [ ] **Step 2:** Run `scripts/test.sh --filter ProcessInspector`. Expected: FAIL.
- [ ] **Step 3: Implement.** Use `proc_pidinfo(PROC_PIDTBSDINFO)` for uid, ppid and start time (nil on failure, which means dead or not permitted), `proc_pidpath` for the path, `proc_pidinfo(PROC_PIDVNODEPATHINFO)` → `pvi_cdir` for cwd (nil when not permitted), and `sysctl([CTL_KERN, KERN_PROCARGS2, pid])` for argv: skip the argc int and the exec path, then read argc NUL-separated strings. An empty array is returned when not permitted.
- [ ] **Step 4:** Run the filtered tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat(core): inspect processes via libproc`.

### Task 4: Project naming + port catalog

**Files:**
- Create: `Sources/PortlightCore/Catalog/ProjectResolver.swift`, `Sources/PortlightCore/Catalog/PortEntry.swift`, `Sources/PortlightCore/Catalog/PortCatalog.swift`, `Tests/PortlightCoreTests/ProjectResolverTests.swift`, `Tests/PortlightCoreTests/PortCatalogTests.swift`

**Interfaces:**
- Consumes: `ListeningSocket`, `Reach`, `ProcessDetails`, `ProcessInspecting` (Tasks 2–3).
- Produces:
  - `public struct ProjectInfo: Sendable, Equatable { public let name: String?; public let label: String }` (label e.g. `"next dev"`; falls back to the process name)
  - `public enum ProjectResolver { public static func resolve(processName: String, details: ProcessDetails?, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> ProjectInfo }`
  - `public struct PortEntry: Sendable, Identifiable, Equatable { public var id: String { "\(proto.rawValue):\(port):\(pid)" }; public let port: UInt16; public let proto: TransportProtocol; public let reach: Reach; public let pid: Int32; public let processName: String; public let project: ProjectInfo; public let details: ProcessDetails? }`
  - `public enum PortCatalog { public static func build(_ sockets: [ListeningSocket], inspector: ProcessInspecting) -> [PortEntry] }` (sorted by port, then proto)

Project name rule: walk up from `workingDirectory` (stop at `$HOME` or `/`) to the first folder containing `package.json`, `.git`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `Gemfile` or `Package.swift`, and use that folder's name. If there's no cwd, try the first argument that is an absolute path. Labels: a `next` arg followed by `dev`/`start` → `"next dev"`/`"next start"`; `vite`; `storybook`; `nest start`; `rails server`; `uvicorn`; `http.server` → `"python http.server"`; executable basename `postgres`/`mongod`/`redis-server`/`mysqld` → that name. Otherwise use the process name.

- [ ] **Step 1: Failing tests**

```swift
@Test func findsProjectFromCwd() {
    let d = details(cwd: "/Users/me/src/my-app/apps/web", args: ["node", "/x/node_modules/.bin/next", "dev"])
    let info = ProjectResolver.resolve(processName: "node", details: d,
        fileExists: { $0 == "/Users/me/src/my-app/.git" })
    #expect(info == ProjectInfo(name: "my-app", label: "next dev"))
}
@Test func fallsBackToProcessName() {
    #expect(ProjectResolver.resolve(processName: "rapportd", details: nil) == ProjectInfo(name: nil, label: "rapportd"))
}
@Test func mergesDualStack() {
    let s = [sock(.tcp, "127.0.0.1", 3000, pid: 10), sock(.tcp, "*", 3000, pid: 10)]
    let e = PortCatalog.build(s, inspector: FakeInspector())
    #expect(e.count == 1); #expect(e[0].reach == .network)
}
@Test func entryWithoutDetails() {
    let e = PortCatalog.build([sock(.tcp, "*", 7000, pid: 999_999)], inspector: FakeInspector())
    #expect(e[0].details == nil); #expect(e[0].project.label == "test")
}
@Test func sortsByPort() {
    let e = PortCatalog.build([sock(.tcp, "*", 8000, pid: 1), sock(.tcp, "*", 3000, pid: 2)], inspector: FakeInspector())
    #expect(e.map(\.port) == [3000, 8000])
}
```

(`sock` builds a `ListeningSocket` with processName `"test"`; `FakeInspector` returns nil unless seeded.)

- [ ] **Step 2:** Run `scripts/test.sh --filter "ProjectResolver|PortCatalog"`. Expected: FAIL.
- [ ] **Step 3:** Implement. Merge key = (proto, port, pid). Reach is `.network` if any merged socket is. Call `inspector.details` once per unique PID.
- [ ] **Step 4:** Run the filtered tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat(core): name projects and build port catalog`.

### Task 5: Scanner, free-port finder, quitting

**Files:**
- Create: `Sources/PortlightCore/Sockets/PortScanner.swift`, `Sources/PortlightCore/Catalog/FreePort.swift`, `Sources/PortlightCore/Process/ProcessController.swift`, `Tests/PortlightCoreTests/PortScannerTests.swift`, `Tests/PortlightCoreTests/FreePortTests.swift`, `Tests/PortlightCoreTests/ProcessControllerTests.swift`

**Interfaces:**
- Consumes: `NetstatParser`, `PortEntry`, `ProcessDetails`, `ProcessIdentity`, `ProcessInspecting`.
- Produces:
  - `public protocol PortScanning: Sendable { func scan() throws -> [ListeningSocket] }`; `public struct NetstatScanner: PortScanning { public init() }` runs `/usr/sbin/netstat -anv -p tcp` and `-p udp` and parses both.
  - `public enum FreePort { public static func owner(of port: UInt16, in entries: [PortEntry]) -> PortEntry?; public static func canBind(_ port: UInt16) -> Bool; public static func nearestFree(to port: UInt16, isFree: (UInt16) -> Bool, limit: Int = 100) -> UInt16? }`. The nearest search goes `port+1 … port+limit` and returns nil if nothing is free.
  - `public enum QuitPolicy { public static func canQuit(_ details: ProcessDetails?, currentUID: uid_t = getuid(), selfPid: Int32 = getpid()) -> Bool }`
  - `public enum TerminateResult: Sendable, Equatable { case exited, stillRunning, failed(Int32) }`
  - `public struct ProcessController: Sendable { public init(inspector: ProcessInspecting = ProcessInspector()); public func terminate(_ identity: ProcessIdentity, grace: Duration = .seconds(3)) async -> TerminateResult; public func forceKill(_ identity: ProcessIdentity) -> TerminateResult; public func isAlive(_ identity: ProcessIdentity) -> Bool }`. Before signalling, check that `identity(pid:)` still matches, so a recycled PID is never signalled.

- [ ] **Step 1: Failing tests**

```swift
@Test func scannerSeesOwnListener() throws {
    let fd = try listen(on: 0)                 // helper: bind 127.0.0.1:0, return (fd, port)
    defer { close(fd.0) }
    let s = try NetstatScanner().scan()
    #expect(s.contains { $0.port == fd.1 && $0.pid == getpid() && $0.reach == .local })
}
@Test func nearestFreeSkipsTaken() {
    #expect(FreePort.nearestFree(to: 3000, isFree: { $0 != 3001 }) == 3002)
    #expect(FreePort.nearestFree(to: 3000, isFree: { _ in false }) == nil)
}
@Test func canBindDetectsBusyPort() throws {
    let fd = try listen(on: 0); defer { close(fd.0) }
    #expect(FreePort.canBind(fd.1) == false)
}
@Test func quitPolicy() {
    #expect(QuitPolicy.canQuit(d(uid: getuid(), path: "/opt/homebrew/bin/node")) == true)
    #expect(QuitPolicy.canQuit(d(uid: 0, path: "/opt/homebrew/bin/node")) == false)
    #expect(QuitPolicy.canQuit(d(uid: getuid(), path: "/usr/libexec/rapportd")) == false)
    #expect(QuitPolicy.canQuit(d(uid: getuid(), path: "/System/Library/x")) == false)
    #expect(QuitPolicy.canQuit(nil) == false)
}
@Test func terminatesSleep() async throws {
    let p = try spawn("/bin/sleep", ["30"])
    let id = try #require(ProcessInspector().identity(pid: p.processIdentifier))
    #expect(await ProcessController().terminate(id) == .exited)
}
@Test func reportsSurvivorOfSigterm() async throws {
    let p = try spawn("/bin/sh", ["-c", "trap '' TERM; sleep 30"])
    try await Task.sleep(for: .milliseconds(200))
    let id = try #require(ProcessInspector().identity(pid: p.processIdentifier))
    let c = ProcessController()
    #expect(await c.terminate(id, grace: .milliseconds(500)) == .stillRunning)
    #expect(c.forceKill(id) == .exited)
}
```

- [ ] **Step 2:** Run `scripts/test.sh --filter "PortScanner|FreePort|ProcessController"`. Expected: FAIL.
- [ ] **Step 3:** Implement. `canBind` tries `bind` on both `INADDR_ANY` and `INADDR_LOOPBACK` with `SO_REUSEADDR` off, and returns true only if both succeed. `terminate` sends SIGTERM, then polls `isAlive` every 100 ms until `grace` runs out. `forceKill` sends SIGKILL, then waits up to 1 s.
- [ ] **Step 4:** Run the filtered tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat(core): scan ports, find free ports, quit safely`.

### Task 6: Stay Awake manager + assertions reader

**Files:**
- Create: `Sources/PortlightCore/Awake/SleepAssertionBackend.swift`, `Sources/PortlightCore/Awake/StayAwakeManager.swift`, `Sources/PortlightCore/Awake/AssertionsParser.swift`, `Tests/PortlightCoreTests/Fixtures/pmset-assertions.txt`, `Tests/PortlightCoreTests/StayAwakeManagerTests.swift`, `Tests/PortlightCoreTests/AssertionsParserTests.swift`

**Interfaces:**
- Consumes: `ProcessIdentity`.
- Produces:
  - `public protocol SleepAssertionBackend: Sendable { func acquire(reason: String) -> UInt32?; func release(_ id: UInt32) }`; `public struct IOPMBackend: SleepAssertionBackend` (`IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep, kIOPMAssertionLevelOn, reason)`).
  - `public struct AwakeHold: Sendable, Identifiable, Equatable { public let id: UUID; public let identity: ProcessIdentity; public let processName: String; public let deadline: Date? }`
  - `@MainActor @Observable public final class StayAwakeManager { public private(set) var holds: [AwakeHold]; public var isActive: Bool { get }; public init(backend: SleepAssertionBackend = IOPMBackend()); public func start(_ identity: ProcessIdentity, name: String, duration: TimeInterval?, now: Date = .now); public func stop(_ id: UUID); public func stopAll(); public func tick(now: Date, isAlive: (ProcessIdentity) -> Bool) }`. A second `start` for the same identity replaces that hold. The reason string is `"Portlight: keeping awake for <name>"`.
  - `public struct SleepAssertion: Sendable, Equatable { public let pid: Int32; public let processName: String; public let type: String; public let name: String; public let onBehalfOf: String? }`; `public enum AssertionsParser { public static func parse(_ pmsetOutput: String) -> [SleepAssertion] }`; `public func currentSleepAssertions() -> [SleepAssertion]` (runs `/usr/bin/pmset -g assertions`).

Fixture `pmset-assertions.txt`: the sample captured during planning (caffeinate ×3 lines including the `on behalf of 'npm' (pid 44844)` detail, plus powerd). This output contains no personal data.

- [ ] **Step 1: Failing tests**

```swift
@MainActor @Test func releasesOnExit() {
    let b = FakeBackend(); let m = StayAwakeManager(backend: b)
    m.start(id1, name: "api", duration: nil)
    m.tick(now: .now, isAlive: { _ in false })
    #expect(m.holds.isEmpty); #expect(b.live.isEmpty)
}
@MainActor @Test func releasesOnDeadline() {
    let b = FakeBackend(); let m = StayAwakeManager(backend: b); let t0 = Date()
    m.start(id1, name: "x", duration: 3600, now: t0)
    m.tick(now: t0.addingTimeInterval(3599), isAlive: { _ in true }); #expect(m.isActive)
    m.tick(now: t0.addingTimeInterval(3600), isAlive: { _ in true }); #expect(!m.isActive)
}
@MainActor @Test func releasesWhenPidReused() {
    let b = FakeBackend(); let m = StayAwakeManager(backend: b)
    m.start(ProcessIdentity(pid: 42, startTime: 1), name: "x", duration: nil)
    m.tick(now: .now, isAlive: { $0 == ProcessIdentity(pid: 42, startTime: 2) })
    #expect(m.holds.isEmpty)
}
@MainActor @Test func multipleHoldsAndStopAll() {
    let b = FakeBackend(); let m = StayAwakeManager(backend: b)
    m.start(id1, name: "a", duration: nil); m.start(id2, name: "b", duration: nil)
    #expect(b.live.count == 2)
    m.start(id1, name: "a", duration: 60); #expect(b.live.count == 2)
    m.stopAll(); #expect(b.live.isEmpty)
}
@Test func parsesAssertions() throws {
    let a = AssertionsParser.parse(try fixture("pmset-assertions.txt"))
    #expect(a.contains { $0.processName == "powerd" && $0.type == "PreventUserIdleSystemSleep" })
    #expect(a.first { $0.pid == 44846 }?.onBehalfOf == "npm")
}
```

- [ ] **Step 2:** Run `scripts/test.sh --filter "StayAwake|Assertions"`. Expected: FAIL.
- [ ] **Step 3:** Implement. Parser: lines matching `^\s+pid (\d+)\((.+?)\): \[0x[0-9a-f]+\] [\d:]+ (\w+) named: "(.*)"`. A following `Details:` line containing `on behalf of '(.+?)'` sets `onBehalfOf` on the preceding assertion.
- [ ] **Step 4:** Run the filtered tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat(core): keep Mac awake per process and read sleep assertions`.

### Task 7: App store, menu-bar panel, ports window

**Files:**
- Create: `Sources/Portlight/Model/PortStore.swift`, `Sources/Portlight/Model/Preferences.swift`, `Sources/Portlight/MenuBar/MenuPanel.swift`, `Sources/Portlight/MenuBar/Tile.swift`, `Sources/Portlight/MenuBar/StayAwakeTile.swift`, `Sources/Portlight/MenuBar/ListeningTile.swift`, `Sources/Portlight/MenuBar/PortCheckTile.swift`, `Sources/Portlight/Window/PortsWindow.swift`, `Sources/Portlight/Window/QuitConfirmation.swift`
- Modify: `Sources/Portlight/PortlightApp.swift`

**Interfaces:**
- Consumes: everything in `PortlightCore` above.
- Produces:
  - `@MainActor @Observable final class PortStore { var entries: [PortEntry]; var lastError: String?; var isVisible: Bool; init(scanner: PortScanning = NetstatScanner(), inspector: ProcessInspecting = ProcessInspector()); func refresh(); func start() }`. `start()` runs a loop that refreshes every 2 s while `isVisible`, else every 15 s, and calls `StayAwakeManager.tick` on each pass. Scans run off the main actor.
  - `Preferences` (`@AppStorage`): `skipQuitConfirmation: Bool`.

UI requirements (mockups `docs/design/mockups-apple-style.html`, option B panel + option C window):
- **Panel** (`MenuBarExtra(.window)`, ~320 pt wide, `.regularMaterial` tiles with 12 pt corners):
  - **Stay Awake**: shows a circle toggle and either "Off" or "<name> · <time left>". Its menu lists the current user's quittable entries with durations Until it exits / 1 h / 2 h / 4 h / Custom…
  - **Listening**: two big numbers, total and On network (orange). Tapping opens the window.
  - **Is port free?**: a number field. It shows "Free" (green) or "In use · <label>" (red) plus "Nearest free: N".
  - Footer: "Show All Ports…" (⌘0, opens the window), "Quit Portlight" (⌘Q).
  - (Clean Up and Lid Closed tiles come in Plans 2 and 3. Don't add placeholders.)
- **Window** (`Window("Portlight", id: "ports")`): a sidebar with only **All Ports** in this plan, and a `Table` with columns Port, Process (label + small project name), Project, Reach (orange "Network" badge), PID. Rows have ☾ (toggle stay awake, accent blue when on) and ✕ (only if `QuitPolicy.canQuit`) buttons. Quit asks for confirmation unless `skipQuitConfirmation`, and the dialog has a "Don't ask again" checkbox. On `.stillRunning`, show an alert "<name> didn't quit." with a **Force Quit** button.
- Menu-bar icon: `light.beacon.max` normally and `light.beacon.max.fill` when any hold is active. The owner reviews whether a blue tint is needed.
- On app termination (`NSApplication.willTerminateNotification`), call `stayAwake.stopAll()`.

- [ ] **Step 1:** Implement `PortStore` and `Preferences`, and wire `PortlightApp` with `@State` store + `StayAwakeManager`, `MenuBarExtra` and `Window`. Add `NSApp.setActivationPolicy(.accessory)` in an `NSApplicationDelegateAdaptor` as a fallback to `LSUIElement`.
- [ ] **Step 2:** Implement the tiles, the panel and the window as specified.
- [ ] **Step 3:** Run `swift build`. Expected: `Build complete!` with no warnings in `Sources/Portlight`.
- [ ] **Step 4:** Run `scripts/test.sh`. Expected: all tests pass.
- [ ] **Step 5:** Commit `feat(app): menu bar panel and ports window`.

### Task 8: App bundle script + manual verification

**Files:**
- Create: `scripts/make-app.sh`, `Resources/Info.plist`
- Modify: `README.md` (Build from source: `scripts/make-app.sh && open build/Portlight.app`)

**Interfaces:**
- Produces: `build/Portlight.app` (universal, ad-hoc signed).

- [ ] **Step 1:** `Info.plist`: `CFBundleIdentifier` `io.github.faizanmohiuddin482.portlight`, `CFBundleName` `Portlight`, `CFBundleExecutable` `Portlight`, `CFBundleShortVersionString` `0.1.0`, `CFBundleVersion` `1`, `LSMinimumSystemVersion` `14.0`, `LSUIElement` true, `NSHumanReadableCopyright` "© 2026 Faizan Mohiuddin. MIT License."
- [ ] **Step 2:** `make-app.sh` (`set -euo pipefail`): `swift build -c release --arch arm64 --arch x86_64`, create `build/Portlight.app/Contents/{MacOS,Resources}`, copy the binary and `Info.plist`, then `codesign --force --sign - build/Portlight.app`.
- [ ] **Step 3:** Run `scripts/make-app.sh && lipo -archs build/Portlight.app/Contents/MacOS/Portlight && codesign -v build/Portlight.app`. Expected: `x86_64 arm64` and no codesign error.
- [ ] **Step 4:** Run `open build/Portlight.app`. Then: `pgrep -x Portlight` returns a PID; start `python3 -m http.server 8765 --bind 127.0.0.1` and check `NetstatScanner` sees it (`swift run` a tiny check or confirm through the window). Hand the owner this manual checklist, because Claude can't see the UI:
  - the icon appears in the menu bar and there's no Dock icon;
  - the panel shows the Listening counts, and port 8765 shows "In use · python http.server";
  - in the window, ☾ on 8765 turns the icon filled, and `pmset -g assertions` lists "Portlight: keeping awake for …";
  - ✕ on 8765 asks for confirmation, then the process is gone and the row disappears within 2 s;
  - after quitting the app, `pmset -g assertions` no longer lists Portlight.
- [ ] **Step 5:** Commit `build: assemble Portlight.app` and push. Confirm CI is green with `gh run watch`.
