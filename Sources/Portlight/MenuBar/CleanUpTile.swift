import PortlightCore
import SwiftUI

/// Ranked suggestions of processes to quit, each with its reason.
struct CleanUpTile: View {
    @Environment(PortStore.self) private var store
    @State private var confirmingAll = false
    @State private var freedMessage: String?

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TileToggle(systemImage: "sparkles", isOn: !store.suggestions.isEmpty)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Clean Up").font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.suggestions.count > 1 { freeAllButton }
                }
                ForEach(store.suggestions.prefix(3)) { suggestion in
                    SuggestionRow(suggestion: suggestion)
                }
            }
        }
    }

    private var subtitle: String {
        if let freedMessage { return freedMessage }
        switch store.suggestions.count {
        case 0: return "Nothing to free"
        case 1: return "1 suggestion"
        case let n: return "\(n) suggestions"
        }
    }

    @ViewBuilder
    private var freeAllButton: some View {
        if confirmingAll {
            Button("Free \(store.suggestions.count)?") {
                confirmingAll = false
                Task {
                    let freed = await store.freeAll()
                    freedMessage = "Freed \(freed)"
                    try? await Task.sleep(for: .seconds(3))
                    freedMessage = nil
                }
            }
            .tint(.red)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button("Free All") {
                confirmingAll = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    confirmingAll = false
                }
            }
            .controlSize(.small)
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(suggestion.label) · \(suggestion.ports.map { ":\($0)" }.joined(separator: " "))")
                    .font(.callout.monospacedDigit())
                    .lineLimit(1)
                Text(suggestion.reason.text)
                    .font(.caption)
                    .foregroundStyle(isExposed ? Color.orange : .secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            InlineQuitButton(identity: suggestion.identity)
                .controlSize(.small)
        }
    }

    private var isExposed: Bool {
        if case .exposedIdle = suggestion.reason { return true }
        return false
    }
}
