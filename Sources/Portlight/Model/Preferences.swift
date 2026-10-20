import Foundation

enum Preferences {
    static let skipQuitConfirmationKey = "skipQuitConfirmation"

    static var skipQuitConfirmation: Bool {
        get { UserDefaults.standard.bool(forKey: skipQuitConfirmationKey) }
        set { UserDefaults.standard.set(newValue, forKey: skipQuitConfirmationKey) }
    }
}
