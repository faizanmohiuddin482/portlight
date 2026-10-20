import Foundation

/// One entry from `pmset -g assertions` — who is keeping the Mac awake.
public struct SleepAssertion: Sendable, Equatable {
    public let pid: Int32
    public let processName: String
    public let type: String
    public let name: String
    /// For `caffeinate -w`-style tools: the process they assert for.
    public let onBehalfOf: String?
}

public enum AssertionsParser {
    nonisolated(unsafe) private static let entry =
        /^\s+pid (\d+)\((.+?)\): \[0x[0-9a-f]+\] [\d:]+ (\w+) named: "(.*)"/
    nonisolated(unsafe) private static let behalf = /on behalf of '(.+?)'/

    public static func parse(_ pmsetOutput: String) -> [SleepAssertion] {
        var result: [SleepAssertion] = []
        for line in pmsetOutput.split(separator: "\n") {
            if let m = try? entry.prefixMatch(in: line), let pid = Int32(m.1) {
                result.append(SleepAssertion(
                    pid: pid, processName: String(m.2), type: String(m.3), name: String(m.4), onBehalfOf: nil))
            } else if line.contains("Details:"), let m = try? behalf.firstMatch(in: line), let last = result.popLast() {
                result.append(SleepAssertion(
                    pid: last.pid, processName: last.processName, type: last.type,
                    name: last.name, onBehalfOf: String(m.1)))
            }
        }
        return result
    }
}

public func currentSleepAssertions() -> [SleepAssertion] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["-g", "assertions"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [] }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return AssertionsParser.parse(String(decoding: data, as: UTF8.self))
}
