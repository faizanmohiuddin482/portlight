import AppKit
import PortlightCore
import SwiftUI

@main
struct PortlightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var stayAwake: StayAwakeManager
    @State private var store: PortStore

    init() {
        let stayAwake = StayAwakeManager()
        let store = PortStore(stayAwake: stayAwake)
        store.start()
        _stayAwake = State(initialValue: stayAwake)
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(store)
                .environment(stayAwake)
        } label: {
            Image(systemName: stayAwake.isActive ? "light.beacon.max.fill" : "light.beacon.max")
        }
        .menuBarExtraStyle(.window)

        Window("Portlight", id: "ports") {
            PortsWindow()
                .environment(store)
                .environment(stayAwake)
        }
        .defaultSize(width: 780, height: 480)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, even when run without the bundle's LSUIElement (e.g. `swift run`).
        NSApp.setActivationPolicy(.accessory)
    }
}
