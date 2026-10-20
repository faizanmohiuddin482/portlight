import PortlightCore
import SwiftUI

/// Quit for the menu-bar panel: Quit → Confirm → (Force Quit if needed).
/// Modal alerts don't belong in a MenuBarExtra, so everything happens in place.
struct InlineQuitButton: View {
    @Environment(PortStore.self) private var store
    let identity: ProcessIdentity

    enum Phase: Equatable { case idle, confirm, working, stubborn, failed }
    @State private var phase: Phase = .idle

    var body: some View {
        switch phase {
        case .idle:
            Button("Quit") { arm() }
        case .confirm:
            Button("Confirm") { run { await store.quit(identity) } }
                .tint(.red)
                .buttonStyle(.borderedProminent)
        case .working:
            ProgressView().controlSize(.small)
        case .stubborn:
            Button("Force Quit") { run { await store.forceQuit(identity) } }
                .tint(.red)
                .buttonStyle(.borderedProminent)
        case .failed:
            Text("Couldn’t quit").foregroundStyle(.red).font(.caption)
        }
    }

    private func arm() {
        phase = .confirm
        Task {
            try? await Task.sleep(for: .seconds(3))
            if phase == .confirm { phase = .idle }
        }
    }

    private func run(_ action: @escaping () async -> TerminateResult) {
        phase = .working
        Task {
            switch await action() {
            case .exited: phase = .idle
            case .stillRunning: phase = .stubborn
            case .failed: phase = .failed
            }
        }
    }
}
