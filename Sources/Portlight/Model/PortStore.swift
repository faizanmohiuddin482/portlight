import AppKit
import Observation
import PortlightCore

/// The app's live view of listening ports. Refreshes every 2 s while a
/// Portlight surface is on screen and every 15 s otherwise, and ticks the
/// stay-awake holds on each pass.
@MainActor @Observable
final class PortStore {
    private(set) var entries: [PortEntry] = []
    private(set) var lastError: String?
    private(set) var visibleSurfaces = 0
    var isVisible: Bool { visibleSurfaces > 0 }

    @ObservationIgnored let stayAwake: StayAwakeManager
    @ObservationIgnored let controller: ProcessController
    @ObservationIgnored private let scanner: PortScanning
    @ObservationIgnored private let inspector: ProcessInspecting
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(
        stayAwake: StayAwakeManager,
        scanner: PortScanning = NetstatScanner(),
        inspector: ProcessInspecting = ProcessInspector()
    ) {
        self.stayAwake = stayAwake
        self.scanner = scanner
        self.inspector = inspector
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

    func refresh() async {
        let scanner = scanner, inspector = inspector
        let result = await Task.detached {
            Result { PortCatalog.build(try scanner.scan(), inspector: inspector) }
        }.value
        switch result {
        case .success(let entries):
            self.entries = entries
            lastError = nil
        case .failure(let error):
            lastError = error.localizedDescription
        }
        stayAwake.tick(now: .now, isAlive: controller.isAlive)
    }

    /// Entries the user may act on, one per process.
    var ownProcesses: [PortEntry] {
        var seen = Set<Int32>()
        return entries.filter { QuitPolicy.canQuit($0.details) && seen.insert($0.pid).inserted }
    }
}
