import Foundation

public enum SuggestionReason: Sendable, Equatable {
    case duplicate(project: String, port: UInt16)
    case orphaned
    case exposedIdle(TimeInterval)
    case idle(TimeInterval)

    /// Strongest reason first.
    var rank: Int {
        switch self {
        case .duplicate: 0
        case .orphaned: 1
        case .exposedIdle: 2
        case .idle: 3
        }
    }

    public var text: String {
        switch self {
        case let .duplicate(project, port): "Duplicate. \(project) is already running on :\(port)"
        case .orphaned: "Orphaned. The terminal that started it has closed"
        case let .exposedIdle(idle): "Open to your network and idle \(Self.format(idle))"
        case let .idle(idle): "Idle \(Self.format(idle)), no connections"
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        return f.string(from: seconds) ?? ""
    }
}

/// A process worth quitting to free its ports, and why.
public struct Suggestion: Sendable, Identifiable, Equatable {
    public var id: ProcessIdentity { identity }
    public let identity: ProcessIdentity
    public let label: String
    public let project: String?
    public let ports: [UInt16]
    public let reason: SuggestionReason
}
