import AppKit
import Carbon
import Foundation

struct FocusShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt
    let keyName: String
    static let standard = FocusShortcut(keyCode: 9, modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue, keyName: "V")

    var flags: NSEvent.ModifierFlags { .init(rawValue: modifiers) }
    var isValid: Bool {
        keyCode < 128 && !flags.intersection([.command, .control]).isEmpty &&
        flags.subtracting([.command, .control, .option, .shift]).isEmpty &&
        !(keyCode == 49 && flags == .command) && !keyName.isEmpty && keyName.count <= 16
    }
    var carbonModifiers: UInt32 {
        (flags.contains(.command) ? UInt32(cmdKey) : 0) |
        (flags.contains(.option) ? UInt32(optionKey) : 0) |
        (flags.contains(.control) ? UInt32(controlKey) : 0) |
        (flags.contains(.shift) ? UInt32(shiftKey) : 0)
    }
    var label: String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") +
        (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + keyName
    }
}

@MainActor final class GlobalShortcut {
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: FocusShortcut?
    private var identifier: UInt32 = 0
    private let signature: OSType = 0x43535652
    var onPress: (() -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            // Carbon application-event handlers run on the application's main event loop.
            return MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                var received = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &received)
                guard status == noErr, received.signature == owner.signature, received.id == owner.identifier else { return OSStatus(eventNotHandledErr) }
                owner.onPress?()
                return noErr
            }
        }, 1, &type, pointer, &handler)
    }

    func replace(with shortcut: FocusShortcut) -> Bool {
        guard shortcut.isValid, handler != nil else { return false }
        if current == shortcut, registration != nil { return true }
        var replacement: EventHotKeyRef?
        let next = identifier &+ 1
        let id = EventHotKeyID(signature: signature, id: next)
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &replacement) == noErr,
              let replacement else { return false }
        if let registration, UnregisterEventHotKey(registration) != noErr {
            UnregisterEventHotKey(replacement)
            return false
        }
        registration = replacement
        current = shortcut
        identifier = next
        return true
    }

    func clear() {
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
        current = nil
    }

    func stop() {
        clear()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
