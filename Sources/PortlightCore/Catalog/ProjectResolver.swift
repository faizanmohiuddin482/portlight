import Foundation

public struct ProjectInfo: Sendable, Equatable {
    /// Project folder name, e.g. "my-app"; nil when we can't tell.
    public let name: String?
    /// What the process is doing, e.g. "next dev"; falls back to the process name.
    public let label: String

    public init(name: String?, label: String) {
        self.name = name
        self.label = label
    }
}

/// Turns `node` on :3000 into "my-app · next dev".
public enum ProjectResolver {
    static let markers = ["package.json", ".git", "Cargo.toml", "go.mod", "pyproject.toml", "Gemfile", "Package.swift"]
    static let knownServers: Set = ["postgres", "mongod", "redis-server", "mysqld"]

    public static func resolve(
        processName: String,
        details: ProcessDetails?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> ProjectInfo {
        guard let details else { return ProjectInfo(name: nil, label: processName) }
        return ProjectInfo(
            name: projectName(details, fileExists: fileExists),
            label: label(details) ?? processName
        )
    }

    private static func projectName(_ d: ProcessDetails, fileExists: (String) -> Bool) -> String? {
        if let cwd = d.workingDirectory, let name = walkUp(from: cwd, fileExists: fileExists) {
            return name
        }
        let absoluteArg = d.arguments.dropFirst().first { $0.hasPrefix("/") }
        return absoluteArg.flatMap {
            walkUp(from: ($0 as NSString).deletingLastPathComponent, fileExists: fileExists)
        }
    }

    private static func walkUp(from start: String, fileExists: (String) -> Bool) -> String? {
        let home = NSHomeDirectory()
        var dir = (start as NSString).standardizingPath
        while dir != "/", dir != home, !dir.isEmpty {
            if markers.contains(where: { fileExists(dir + "/" + $0) }) {
                return (dir as NSString).lastPathComponent
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    private static func label(_ d: ProcessDetails) -> String? {
        let exe = ((d.executablePath ?? d.arguments.first ?? "") as NSString).lastPathComponent
        if knownServers.contains(exe) { return exe }

        let words = d.arguments.map { ($0 as NSString).lastPathComponent }
        func followed(_ cmd: String, by subs: Set<String>) -> String? {
            guard let i = words.firstIndex(of: cmd), i + 1 < words.count, subs.contains(words[i + 1]) else { return nil }
            return "\(cmd) \(words[i + 1])"
        }
        if let l = followed("next", by: ["dev", "start"]) { return l }
        if let l = followed("nest", by: ["start"]) { return l }
        if followed("rails", by: ["server", "s"]) != nil { return "rails server" }
        if words.contains("http.server") { return "python http.server" }
        if words.contains("vite") { return "vite" }
        if words.contains(where: { $0 == "storybook" || $0 == "start-storybook" }) { return "storybook" }
        if words.contains("uvicorn") { return "uvicorn" }
        return nil
    }
}
