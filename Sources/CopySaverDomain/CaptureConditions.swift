public enum ClipboardPermission: Equatable, Sendable {
    case unknown, allowed, denied
}

public enum CaptureAvailability: Equatable, Sendable {
    case locked, disabled, paused, permissionNeeded, storageUnavailable, ready
}

/// Capture preference, manual pause, OS permission and vault state are independent inputs.
/// A platform adapter may inspect clipboard metadata to resolve permission; this gate
/// controls admission of payload reads and persistence, not permission-request UI.
public struct CaptureConditions: Equatable, Sendable {
    public var vaultUnlocked: Bool
    public var captureEnabled: Bool
    public var manuallyPaused: Bool
    public var clipboardPermission: ClipboardPermission
    public var storageWritable: Bool

    public init(
        vaultUnlocked: Bool = false, captureEnabled: Bool = false,
        manuallyPaused: Bool = false, clipboardPermission: ClipboardPermission = .unknown,
        storageWritable: Bool = true
    ) {
        self.vaultUnlocked = vaultUnlocked
        self.captureEnabled = captureEnabled
        self.manuallyPaused = manuallyPaused
        self.clipboardPermission = clipboardPermission
        self.storageWritable = storageWritable
    }

    public var availability: CaptureAvailability {
        if !vaultUnlocked { return .locked }
        if !captureEnabled { return .disabled }
        if manuallyPaused { return .paused }
        if clipboardPermission != .allowed { return .permissionNeeded }
        if !storageWritable { return .storageUnavailable }
        return .ready
    }

    public var canCapture: Bool { availability == .ready }
}
