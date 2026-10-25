import Foundation
import Testing
@testable import PortlightCore

@Test func findsProjectFromCwd() {
    let d = details(cwd: "/Users/me/src/my-app/apps/web", args: ["node", "/x/node_modules/.bin/next", "dev"])
    let info = ProjectResolver.resolve(
        processName: "node", details: d,
        fileExists: { $0 == "/Users/me/src/my-app/.git" })
    #expect(info == ProjectInfo(name: "my-app", label: "next dev"))
}

@Test func nearestMarkerWins() {
    let d = details(cwd: "/Users/me/src/mono/apps/web", args: ["node", "vite"])
    let info = ProjectResolver.resolve(
        processName: "node", details: d,
        fileExists: { $0 == "/Users/me/src/mono/apps/web/package.json" || $0 == "/Users/me/src/mono/.git" })
    #expect(info == ProjectInfo(name: "web", label: "vite"))
}

@Test func fallsBackToProcessName() {
    #expect(ProjectResolver.resolve(processName: "rapportd", details: nil) == ProjectInfo(name: nil, label: "rapportd"))
}

@Test func labelsKnownCommands() {
    let py = details(args: ["/usr/bin/python3", "-m", "http.server", "8765"])
    #expect(ProjectResolver.resolve(processName: "Python", details: py, fileExists: { _ in false }).label == "python http.server")
    let pg = details(args: ["/opt/homebrew/opt/postgresql@16/bin/postgres", "-D", "/x"])
    #expect(ProjectResolver.resolve(processName: "postgres", details: pg, fileExists: { _ in false }).label == "postgres")
    let nest = details(args: ["node", "/app/node_modules/.bin/nest", "start", "--watch"])
    #expect(ProjectResolver.resolve(processName: "node", details: nest, fileExists: { _ in false }).label == "nest start")
}

@Test func usesAbsoluteArgWhenNoCwd() {
    let d = details(cwd: nil, args: ["node", "/Users/me/src/api/dist/main.js"])
    let info = ProjectResolver.resolve(
        processName: "node", details: d, fileExists: { $0 == "/Users/me/src/api/package.json" })
    #expect(info.name == "api")
}

@Test func stopsAtHome() {
    let d = details(cwd: NSHomeDirectory(), args: ["node"])
    let info = ProjectResolver.resolve(processName: "node", details: d, fileExists: { _ in true })
    #expect(info.name == nil)
}
