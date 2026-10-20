import PortlightCore
import SwiftUI

struct PortsWindow: View {
    @Environment(PortStore.self) private var store
    @State private var section: Section? = .all

    enum Section: Hashable { case all }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("All Ports", systemImage: "point.3.connected.trianglepath.dotted").tag(Section.all)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            PortsTable(entries: store.entries)
                .navigationTitle("All Ports")
                .navigationSubtitle(store.lastError ?? "\(store.entries.count) listening")
        }
        .onAppear { store.surfaceAppeared() }
        .onDisappear { store.surfaceDisappeared() }
    }
}

struct PortsTable: View {
    let entries: [PortEntry]

    var body: some View {
        Table(entries) {
            TableColumn("Port") { e in
                HStack(spacing: 4) {
                    Text(String(e.port)).fontWeight(.semibold).monospacedDigit()
                    if e.proto == .udp { Text("UDP").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .width(min: 60, ideal: 70)
            TableColumn("Process") { e in
                VStack(alignment: .leading, spacing: 0) {
                    Text(e.project.label)
                    if e.project.label != e.processName {
                        Text(e.processName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 140, ideal: 200)
            TableColumn("Project") { e in
                Text(e.project.name ?? "—").foregroundStyle(e.project.name == nil ? .secondary : .primary)
            }
            TableColumn("Reach") { e in ReachBadge(reach: e.reach) }
                .width(min: 60, ideal: 80)
            TableColumn("PID") { e in Text(String(e.pid)).monospacedDigit().foregroundStyle(.secondary) }
                .width(min: 50, ideal: 60)
            TableColumn("") { e in RowActions(entry: e) }
                .width(56)
        }
    }
}

private struct ReachBadge: View {
    let reach: Reach

    var body: some View {
        switch reach {
        case .local:
            Text("Local").foregroundStyle(.secondary)
        case .network:
            Text("Network")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                .help("Reachable by other devices on your network")
        }
    }
}

private struct RowActions: View {
    @Environment(PortStore.self) private var store
    @Environment(StayAwakeManager.self) private var stayAwake
    let entry: PortEntry

    private var hold: AwakeHold? {
        stayAwake.holds.first { $0.identity == entry.details?.identity }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if let hold { stayAwake.stop(hold.id) } else if let id = entry.details?.identity {
                    stayAwake.start(id, name: entry.project.label, duration: nil)
                }
            } label: {
                Image(systemName: hold == nil ? "moon" : "moon.fill")
                    .foregroundStyle(hold == nil ? Color.secondary : Color.accentColor)
            }
            .disabled(entry.details == nil)
            .help(hold == nil ? "Keep the Mac awake while this runs" : "Stop keeping the Mac awake")

            if QuitPolicy.canQuit(entry.details) {
                Button {
                    Task { await QuitFlow.quit(entry, store: store) }
                } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                }
                .help("Quit this process")
            }
        }
        .buttonStyle(.borderless)
    }
}
