import AppKit
import SwiftUI

private struct CopySaverWindowIsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var copySaverWindowIsKey: Bool {
        get { self[CopySaverWindowIsKey.self] }
        set { self[CopySaverWindowIsKey.self] = newValue }
    }
}

/// Observe the hosting window, rather than the active appearance of the app.
/// The empty background view never becomes a responder or intercepts pointer input.
struct WindowKeyObserver: NSViewRepresentable {
    @Binding var isKey: Bool

    func makeNSView(context: Context) -> WindowKeyObservationView {
        let view = WindowKeyObservationView(frame: .zero)
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: WindowKeyObservationView, context: Context) {
        view.onKeyChange = { value in if isKey != value { isKey = value } }
        view.reportKeyState()
    }

    static func dismantleNSView(_ view: WindowKeyObservationView, coordinator: ()) {
        view.stopObserving()
    }
}

@MainActor final class WindowKeyObservationView: NSView {
    var onKeyChange: ((Bool) -> Void)?
    private var update: Task<Void, Never>?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(keyChanged), name: name, object: window)
            }
        }
        reportKeyState()
    }

    @objc private func keyChanged(_ notification: Notification) { reportKeyState() }

    func reportKeyState() {
        // Defer SwiftUI binding writes until after the representable's update.
        // Read the current window when delivered, so moves cannot publish stale state.
        update?.cancel()
        update = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            self.onKeyChange?(self.window?.isKeyWindow ?? false)
        }
    }

    func stopObserving() {
        update?.cancel()
        update = nil
        onKeyChange = nil
        NotificationCenter.default.removeObserver(self)
    }

    func finishPendingUpdate() async { await update?.value }
}
