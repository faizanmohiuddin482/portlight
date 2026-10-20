import SwiftUI

@main
struct PortlightApp: App {
    var body: some Scene {
        MenuBarExtra("Portlight", systemImage: "light.beacon.max") {
            Text("Portlight")
        }
        .menuBarExtraStyle(.window)
    }
}
