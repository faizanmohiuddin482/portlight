import PortlightCore
import SwiftUI

struct PortCheckTile: View {
    @Environment(PortStore.self) private var store
    @State private var text = ""

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 6) {
                Text("Is port free?").font(.headline)
                HStack {
                    TextField("3000", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .font(.body.monospacedDigit())
                    Spacer()
                    if let port { verdict(port) }
                }
                if let port, let owner = FreePort.owner(of: port, in: store.entries),
                   QuitPolicy.canQuit(owner.details), let identity = owner.details?.identity {
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.suggestion(for: owner.pid)?.reason.text ?? "In use now")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        InlineQuitButton(identity: identity).controlSize(.small)
                    }
                }
                if let port, !isFree(port), let next = FreePort.nearestFree(to: port, isFree: isFree) {
                    HStack(spacing: 4) {
                        Text("Nearest free:").foregroundStyle(.secondary)
                        Text(String(next)).foregroundStyle(Color.accentColor).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var port: UInt16? {
        UInt16(text.trimmingCharacters(in: .whitespaces)).flatMap { $0 == 0 ? nil : $0 }
    }

    private func isFree(_ port: UInt16) -> Bool {
        FreePort.owner(of: port, in: store.entries) == nil && FreePort.canBind(port)
    }

    @ViewBuilder
    private func verdict(_ port: UInt16) -> some View {
        if let owner = FreePort.owner(of: port, in: store.entries) {
            Text("In use · \(owner.project.label)").foregroundStyle(.red)
        } else if !FreePort.canBind(port) {
            Text("In use · System").foregroundStyle(.red)
        } else {
            Text("Free").foregroundStyle(.green)
        }
    }
}
