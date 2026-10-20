import IOKit.pwr_mgt

public protocol SleepAssertionBackend: Sendable {
    func acquire(reason: String) -> UInt32?
    func release(_ id: UInt32)
}

/// Prevents idle *system* sleep; the display is still allowed to sleep.
public struct IOPMBackend: SleepAssertionBackend {
    public init() {}

    public func acquire(reason: String) -> UInt32? {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    public func release(_ id: UInt32) {
        IOPMAssertionRelease(id)
    }
}
