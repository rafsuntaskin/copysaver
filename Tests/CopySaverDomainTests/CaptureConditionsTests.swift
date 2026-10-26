import CopySaverDomain
import Testing

@Test func captureRequiresEveryIndependentCondition() {
    for unlocked in [false, true] {
        for enabled in [false, true] {
            for paused in [false, true] {
                for permission in [ClipboardPermission.unknown, .allowed, .denied] {
                    for writable in [false, true] {
                        let conditions = CaptureConditions(
                            vaultUnlocked: unlocked, captureEnabled: enabled, manuallyPaused: paused,
                            clipboardPermission: permission, storageWritable: writable
                        )
                        #expect(conditions.canCapture == (unlocked && enabled && !paused && permission == .allowed && writable))
                    }
                }
            }
        }
    }
}

@Test func unlockingDoesNotResetManualPauseOrUserPreference() {
    var conditions = CaptureConditions(captureEnabled: true, manuallyPaused: true, clipboardPermission: .allowed)
    #expect(conditions.availability == .locked)
    conditions.vaultUnlocked = true
    #expect(conditions.availability == .paused)
    conditions.manuallyPaused = false
    #expect(conditions.availability == .ready)
    conditions.storageWritable = false
    #expect(conditions.availability == .storageUnavailable)
    conditions.captureEnabled = false
    #expect(conditions.availability == .disabled)
}
