import PortlightCore
import SwiftUI

struct MenuPanel: View {
    @Environment(PortStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 8) {
            StayAwakeTile()
            ListeningTile(showAll: showAllPorts)
            CleanUpTile()
            PortCheckTile()
            Divider().padding(.vertical, 2)
            footer
        }
        .padding(10)
        .frame(width: 320)
        .onAppear { store.surfaceAppeared() }
        .onDisappear { store.surfaceDisappeared() }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            FooterButton(title: "Show All Ports…", action: showAllPorts)
                .keyboardShortcut("0")
            FooterButton(title: "Quit Portlight") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func showAllPorts() {
        openWindow(id: "ports")
        NSApp.activate()
    }
}

private struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
