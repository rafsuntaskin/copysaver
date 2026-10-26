import CopySaverDomain
@testable import CopySaverDesktop
import Foundation
import Testing

@MainActor private final class Input: ClipboardInput {
    var changeCount = 0
    var permission: ClipboardPermission = .allowed
    var activeApplication: String? = "org.example.editor"
    var activeApplicationName: String? = "Synthetic editor"
    var types: Set<String> = ["public.utf8-plain-text"]
    var itemCount = 1
    var text = "Synthetic example"
    var hint: String?
    var reads = 0
    var race = false
    func readText() -> String? { reads += 1; if race { changeCount += 1 }; return text }
    func sourceHint() -> String? { hint }
}
private func enabled() -> CaptureConditions { CaptureConditions(vaultUnlocked: true, captureEnabled: true, clipboardPermission: .allowed) }

@MainActor @Test func startupPauseAndPermissionRestorationOnlyReadSubsequentChanges() {
    let input = Input()
    let monitor = ClipboardMonitor(input: input, ownIdentifier: "org.example.CopySaver")
    #expect(monitor.poll(conditions: enabled(), exclusions: []) == nil)
    #expect(input.reads == 0)
    input.changeCount += 1
    #expect(monitor.poll(conditions: enabled(), exclusions: [])?.text == input.text)
    var paused = enabled(); paused.manuallyPaused = true
    input.changeCount += 1
    #expect(monitor.poll(conditions: paused, exclusions: []) == nil)
    #expect(monitor.poll(conditions: enabled(), exclusions: []) == nil)
    input.permission = .denied; input.changeCount += 1
    #expect(monitor.poll(conditions: enabled(), exclusions: []) == nil)
    input.permission = .allowed
    #expect(monitor.poll(conditions: enabled(), exclusions: []) == nil)
    #expect(input.reads == 1)
}

@MainActor @Test func confidentialMarkersSelfWritesAndExclusionsDoNotReadText() {
    let input = Input()
    let monitor = ClipboardMonitor(input: input, ownIdentifier: "org.example.CopySaver")
    _ = monitor.poll(conditions: enabled(), exclusions: [])
    input.types.insert("org.nspasteboard.ConcealedType"); input.changeCount += 1
    #expect(monitor.poll(conditions: enabled(), exclusions: []) == nil)
    input.types.remove("org.nspasteboard.ConcealedType"); input.hint = "org.example.CopySaver"; input.changeCount += 1
    #expect(monitor.poll(conditions: enabled(), exclusions: []) == nil)
    input.hint = nil; input.activeApplication = "org.example.secret"; input.changeCount += 1
    _ = monitor.poll(conditions: enabled(), exclusions: ["org.example.secret"])
    input.changeCount += 1
    #expect(monitor.poll(conditions: enabled(), exclusions: ["org.example.secret"]) == nil)
    #expect(input.reads == 0)
}

@MainActor @Test func midReadAndActivationRacesAreDroppedAndCounterWrapIsAccepted() {
    let input = Input()
    let monitor = ClipboardMonitor(input: input, ownIdentifier: "org.example.CopySaver")
    _ = monitor.poll(conditions: enabled(), exclusions: [])
    input.race = true; input.changeCount = 1
    #expect(monitor.poll(conditions: enabled(), exclusions: []) == nil)
    input.race = false; input.activeApplication = "org.example.other"
    #expect(monitor.poll(conditions: enabled(), exclusions: []) == nil)
    input.changeCount = Int.min
    #expect(monitor.poll(conditions: enabled(), exclusions: []) != nil)
    // Activation observer rebaselines even a fast excluded-app round trip between polls.
    input.changeCount += 1; monitor.rebaseline()
    #expect(monitor.poll(conditions: enabled(), exclusions: []) == nil)
}
