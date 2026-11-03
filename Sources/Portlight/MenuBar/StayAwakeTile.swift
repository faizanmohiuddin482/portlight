import PortlightCore
import SwiftUI

struct StayAwakeTile: View {
    @Environment(PortStore.self) private var store
    @Environment(StayAwakeManager.self) private var stayAwake
    @State private var customTarget: CustomTarget?
    @State private var customHours = 3

    private enum CustomTarget: Equatable {
        case mac
        case process(PortEntry)
    }

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        if stayAwake.isActive { stayAwake.stopAll() } else { stayAwake.startMac(duration: nil) }
                    } label: {
                        TileToggle(systemImage: "moon.fill", isOn: stayAwake.isActive)
                    }
                    .buttonStyle(.plain)
                    .help(stayAwake.isActive ? "Let the Mac sleep again" : "Keep this Mac awake until you turn it off")

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
            Menu("This Mac") {
                Button("Until I Turn It Off") { stayAwake.startMac(duration: nil) }
                durationButtons { stayAwake.startMac(duration: $0) }
                Divider()
                Button("Custom…") { customTarget = .mac }
                if stayAwake.macHold != nil {
                    Divider()
                    Button("Turn Off") { stayAwake.stopMac() }
                }
            }
            Divider()
            if store.ownProcesses.isEmpty {
                Text("No processes of yours are listening")
            }
            ForEach(store.ownProcesses) { entry in
                Menu("\(entry.project.label) · :\(String(entry.port))") {
                    Button("Until It Exits") { keepAwake(entry, nil) }
                    durationButtons { keepAwake(entry, $0) }
                    Divider()
                    Button("Custom…") { customTarget = .process(entry) }
                }
            }
        } label: {
            Image(systemName: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Keep the Mac awake, for a while or for a process")
    }

    @ViewBuilder
    private func durationButtons(_ start: @escaping (TimeInterval) -> Void) -> some View {
        Button("1 Hour") { start(3600) }
        Button("2 Hours") { start(7200) }
        Button("4 Hours") { start(14400) }
    }

    private func customRow(_ target: CustomTarget) -> some View {
        HStack {
            Stepper("\(customHours) h", value: $customHours, in: 1...24)
                .font(.callout)
            Spacer()
            Button("Cancel") { customTarget = nil }
            Button("Start") {
                let duration = TimeInterval(customHours) * 3600
                switch target {
                case .mac: stayAwake.startMac(duration: duration)
                case .process(let entry): keepAwake(entry, duration)
                }
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
        let processes = stayAwake.holds
        switch (stayAwake.macHold, processes.count) {
        case (nil, 0):
            return "Off"
        case (let mac?, 0):
            return Self.macStatus(mac, now: now, openEnded: "until turned off")
        case (let mac?, let n):
            return "\(Self.macStatus(mac, now: now, openEnded: nil)) + \(n) \(n == 1 ? "process" : "processes")"
        case (nil, 1):
            let hold = processes[0]
            guard let deadline = hold.deadline else { return "\(hold.processName) · until it exits" }
            return "\(hold.processName) · \(Self.remaining(deadline.timeIntervalSince(now))) left"
        case (nil, let n):
            return "\(n) processes"
        }
    }

    private static func macStatus(_ mac: MacHold, now: Date, openEnded: String?) -> String {
        if let deadline = mac.deadline { return "This Mac · \(remaining(deadline.timeIntervalSince(now))) left" }
        return openEnded.map { "This Mac · \($0)" } ?? "This Mac"
    }

    static func remaining(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        return f.string(from: max(60, seconds)) ?? ""
    }
}
