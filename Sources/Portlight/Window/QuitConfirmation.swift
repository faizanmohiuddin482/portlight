import AppKit
import PortlightCore

/// Quit flow: confirm (unless the user opted out), SIGTERM, then offer
/// Force Quit if the process is still running after the grace period.
@MainActor
enum QuitFlow {
    static func quit(_ entry: PortEntry, store: PortStore) async {
        guard let identity = entry.details?.identity else { return }
        let name = entry.project.label

        if !Preferences.skipQuitConfirmation {
            let alert = NSAlert()
            alert.messageText = "Quit “\(name)”?"
            alert.informativeText = "PID \(entry.pid) is listening on port \(entry.port)."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don’t ask again"
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if alert.suppressionButton?.state == .on { Preferences.skipQuitConfirmation = true }
        }

        if await store.controller.terminate(identity) == .stillRunning {
            let alert = NSAlert()
            alert.messageText = "“\(name)” didn’t quit."
            alert.informativeText = "It is still running after 3 seconds."
            alert.addButton(withTitle: "Force Quit")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                _ = store.controller.forceKill(identity)
            }
        }
        await store.refresh()
    }
}
