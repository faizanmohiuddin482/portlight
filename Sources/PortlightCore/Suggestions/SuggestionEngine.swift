import Foundation

/// Decides which processes to suggest quitting. Pure: everything it needs
/// (activity, holds, the clock) is passed in.
public enum SuggestionEngine {
    public static let idleThreshold: TimeInterval = 2 * 3600
    public static let recentWindow: TimeInterval = 5 * 60
    /// Launchers like `caddy start` legitimately leave servers parented to launchd,
    /// so an orphan must also be quiet for a while before it is suggested.
    public static let orphanIdle: TimeInterval = 30 * 60

    public static func suggest(
        entries: [PortEntry],
        lastActive: (ProcessIdentity) -> Date?,
        held: Set<ProcessIdentity>,
        now: Date
    ) -> [Suggestion] {
        let processes = Dictionary(grouping: entries.filter { $0.details != nil }) { $0.details!.identity }

        let suggestions: [(Suggestion, idle: TimeInterval)] = processes.compactMap { identity, entries in
            let first = entries[0]
            guard let details = first.details,
                  !held.contains(identity),
                  QuitPolicy.canQuit(details),
                  !isDatabase(first),
                  let active = lastActive(identity)
            else { return nil }

            // The older of a duplicate pair is the one to keep, whatever its idle time.
            if newerTwinExists(of: first, details: details, in: processes) { return nil }

            let idle = now.timeIntervalSince(active)
            guard idle >= recentWindow,
                  let reason = reason(for: first, details: details, entries: entries, all: processes, idle: idle)
            else { return nil }

            let suggestion = Suggestion(
                identity: identity, label: first.project.label, project: first.project.name,
                ports: entries.map(\.port).sorted(), reason: reason
            )
            return (suggestion, idle)
        }

        return suggestions
            .sorted { ($0.0.reason.rank, -$0.idle, $0.0.ports[0]) < ($1.0.reason.rank, -$1.idle, $1.0.ports[0]) }
            .map(\.0)
    }

    private static func reason(
        for entry: PortEntry, details: ProcessDetails, entries: [PortEntry],
        all: [ProcessIdentity: [PortEntry]], idle: TimeInterval
    ) -> SuggestionReason? {
        if let project = entry.project.name, let older = olderTwin(of: entry, details: details, in: all) {
            return .duplicate(project: project, port: older)
        }
        let inAppBundle = details.executablePath?.contains(".app/") ?? false
        if details.parentPid == 1, !details.isGroupLeader, !inAppBundle,
           entry.project.name != nil, idle >= orphanIdle {
            return .orphaned
        }
        guard idle >= idleThreshold else { return nil }
        return entries.contains { $0.reach == .network } ? .exposedIdle(idle) : .idle(idle)
    }

    private static func newerTwinExists(
        of entry: PortEntry, details: ProcessDetails, in all: [ProcessIdentity: [PortEntry]]
    ) -> Bool {
        all.values.contains { others in
            guard let o = others.first, let od = o.details else { return false }
            return isTwin(o, od, of: entry, details) && od.identity.startTime > details.identity.startTime
        }
    }

    /// Same recognised command in the same project, same user. A fallback label
    /// (just the process name, e.g. "node" for `node api.js` and `node mock.js`)
    /// says nothing about what the process does, so it never makes a duplicate.
    private static func isTwin(_ o: PortEntry, _ od: ProcessDetails, of entry: PortEntry, _ details: ProcessDetails) -> Bool {
        entry.project.name != nil
            && entry.project.label != entry.processName
            && od.identity != details.identity
            && od.uid == details.uid
            && o.project == entry.project
    }

    /// The lowest port of an older process running the same thing in the same project.
    private static func olderTwin(
        of entry: PortEntry, details: ProcessDetails, in all: [ProcessIdentity: [PortEntry]]
    ) -> UInt16? {
        all.values
            .compactMap { others -> UInt16? in
                guard let o = others.first, let od = o.details,
                      isTwin(o, od, of: entry, details),
                      od.identity.startTime < details.identity.startTime
                else { return nil }
                return others.map(\.port).min()
            }
            .min()
    }

    private static func isDatabase(_ entry: PortEntry) -> Bool {
        let exe = ((entry.details?.executablePath ?? "") as NSString).lastPathComponent
        return ProjectResolver.knownServers.contains(exe) || ProjectResolver.knownServers.contains(entry.project.label)
    }
}
