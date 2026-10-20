import PortlightCore
import SwiftUI

struct ListeningTile: View {
    @Environment(PortStore.self) private var store
    let showAll: () -> Void

    var body: some View {
        Button(action: showAll) {
            Tile {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Listening").font(.headline)
                    HStack(spacing: 24) {
                        stat(store.entries.count, "ports", .primary)
                        stat(store.entries.filter { $0.reach == .network }.count, "on network", .orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .help("Show all ports")
    }

    private func stat(_ value: Int, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }
}
