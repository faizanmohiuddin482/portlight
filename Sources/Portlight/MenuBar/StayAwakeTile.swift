import PortlightCore
import SwiftUI

struct StayAwakeTile: View {
    @Environment(PortStore.self) private var store
    @Environment(StayAwakeManager.self) private var stayAwake
    @State private var customTarget: PortEntry?
    @State private var customHours = 3

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        if stayAwake.isActive { stayAwake.stopAll() }
                    } label: {
                        TileToggle(systemImage: "moon.fill", isOn: stayAwake.isActive)
                    }
                    .buttonStyle(.plain)
                    .disabled(!stayAwake.isActive)
                    .help(stayAwake.isActive ? "Let the Mac sleep again" : "Pick a process to keep the Mac awake for")

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Stay Awake").font(.headline)
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(status(now: context.date))
                                .font(.caption)
                                .foregroundStyle(stayAwake.isActive ? Color.accentColor : .secondary)
                        }
                    }
                    Spacer()
                    picker
                }
                if let target = customTarget { customRow(target) }
            }
        }
    }

    private var picker: some View {
        Menu {
            if store.ownProcesses.isEmpty {
                Text("No processes of yours are listening")
            }
            ForEach(store.ownProcesses) { entry in
                Menu("\(entry.project.label) · :\(String(entry.port))") {
                    Button("Until It Exits") { keepAwake(entry, nil) }
                    Button("1 Hour") { keepAwake(entry, 3600) }
                    Button("2 Hours") { keepAwake(entry, 7200) }
                    Button("4 Hours") { keepAwake(entry, 14400) }
                    Divider()
                    Button("Custom…") { customTarget = entry }
                }
            }
        } label: {
            Image(systemName: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Keep the Mac awake for a process")
    }

    private func customRow(_ entry: PortEntry) -> some View {
        HStack {
            Stepper("\(customHours) h", value: $customHours, in: 1...24)
                .font(.callout)
            Spacer()
            Button("Cancel") { customTarget = nil }
            Button("Start") {
                keepAwake(entry, TimeInterval(customHours) * 3600)
                customTarget = nil
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
    }

    private func keepAwake(_ entry: PortEntry, _ duration: TimeInterval?) {
        guard let identity = entry.details?.identity else { return }
        stayAwake.start(identity, name: entry.project.label, duration: duration)
    }

    private func status(now: Date) -> String {
        switch stayAwake.holds.count {
        case 0: return "Off"
        case 1:
            let hold = stayAwake.holds[0]
            guard let deadline = hold.deadline else { return "\(hold.processName) · until it exits" }
            return "\(hold.processName) · \(Self.remaining(deadline.timeIntervalSince(now))) left"
        case let n: return "\(n) processes"
        }
    }

    static func remaining(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        return f.string(from: max(60, seconds)) ?? ""
    }
}
