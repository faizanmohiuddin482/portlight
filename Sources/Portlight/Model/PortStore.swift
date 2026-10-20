import AppKit
import Observation
import PortlightCore

/// The app's live view of listening ports. Refreshes every 2 s while a
/// Portlight surface is on screen and every 15 s otherwise, ticks the
/// stay-awake holds, and keeps the free-up suggestions current.
@MainActor @Observable
final class PortStore {
    private(set) var entries: [PortEntry] = []
    private(set) var suggestions: [Suggestion] = []
    private(set) var lastError: String?
    private(set) var visibleSurfaces = 0
    var isVisible: Bool { visibleSurfaces > 0 }

    @ObservationIgnored let stayAwake: StayAwakeManager
    @ObservationIgnored let controller: ProcessController
    @ObservationIgnored private let scanner: PortScanning
    @ObservationIgnored private let inspector: ProcessInspecting
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var tracker = ActivityTracker()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var startedScans = 0
    @ObservationIgnored private var appliedScan = 0

    init(
        stayAwake: StayAwakeManager,
        scanner: PortScanning = NetstatScanner(),
        inspector: ProcessInspecting = ProcessInspector(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.stayAwake = stayAwake
        self.scanner = scanner
        self.inspector = inspector
        self.clock = clock
        self.controller = ProcessController(inspector: inspector)
    }

    func start() {
        guard loop == nil else { return }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [stayAwake] _ in
            MainActor.assumeIsolated { stayAwake.stopAll() }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.isVisible ? .seconds(2) : .seconds(15))
            }
        }
    }

    func surfaceAppeared() {
        visibleSurfaces += 1
        if visibleSurfaces == 1 { Task { await refresh() } }
    }

    func surfaceDisappeared() {
        visibleSurfaces = max(0, visibleSurfaces - 1)
    }

    private struct Snapshot: Sendable {
        let entries: [PortEntry]
        let samples: [ActivitySample]
        let connections: [ConnectionKey: Int]
    }

    func refresh() async {
        startedScans += 1
        let scan = startedScans
        let scanner = scanner, inspector = inspector
        let result = await Task.detached {
            Result { () throws -> Snapshot in
                let scanned = try scanner.scan()
                let entries = PortCatalog.build(scanned.listening, inspector: inspector)
                let byProcess = Dictionary(grouping: entries.filter { $0.details != nil }) { $0.details!.identity }
                let samples = byProcess.map { identity, entries in
                    ActivitySample(identity: identity, ports: entries.map(\.port), cpuTime: inspector.cpuTime(pid: identity.pid))
                }
                return Snapshot(entries: entries, samples: samples, connections: scanned.connections)
            }
        }.value
        // Scans can overlap (timer, panel opening, after a quit); never let an
        // older one overwrite a newer one, or a just-quit row reappears.
        guard scan > appliedScan else { return }
        appliedScan = scan

        let now = clock()
        switch result {
        case .success(let snapshot):
            entries = snapshot.entries
            tracker.record(snapshot.samples, connections: snapshot.connections, now: now)
            lastError = nil
        case .failure(let error):
            lastError = error.localizedDescription
        }
        stayAwake.tick(now: now, isAlive: controller.isAlive)
        suggestions = SuggestionEngine.suggest(
            entries: entries,
            lastActive: tracker.lastActive,
            held: Set(stayAwake.holds.map(\.identity)),
            now: now
        )
    }

    func suggestion(for pid: Int32) -> Suggestion? {
        suggestions.first { $0.identity.pid == pid }
    }

    /// Entries the user may act on, one per process.
    var ownProcesses: [PortEntry] {
        var seen = Set<Int32>()
        return entries.filter { QuitPolicy.canQuit($0.details) && seen.insert($0.pid).inserted }
    }

    func quit(_ identity: ProcessIdentity) async -> TerminateResult {
        let result = await controller.terminate(identity)
        await refresh()
        return result
    }

    func forceQuit(_ identity: ProcessIdentity) async -> TerminateResult {
        let controller = controller
        let result = await Task.detached { controller.forceKill(identity) }.value
        await refresh()
        return result
    }

    /// Quits the suggestions the user saw when they confirmed, skipping any that
    /// are no longer suggested. Returns how many quit.
    func freeAll(_ shown: [ProcessIdentity]) async -> Int {
        let current = Set(suggestions.map(\.identity))
        let targets = shown.filter(current.contains)
        var freed = 0
        await withTaskGroup(of: TerminateResult.self) { group in
            for identity in targets {
                group.addTask { [controller] in await controller.terminate(identity) }
            }
            for await result in group where result == .exited { freed += 1 }
        }
        await refresh()
        return freed
    }
}
