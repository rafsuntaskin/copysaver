import AppKit
import Carbon
import CopySaverPlatform
import CoreGraphics
import SwiftUI

public enum CopySaverApplication {
    @MainActor public static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let preview: Bool
        #if DEBUG
        preview = CommandLine.arguments.contains("--ui-preview")
        #else
        preview = false
        if CommandLine.arguments.contains("--ui-preview") { return }
        #endif
        let delegate = ApplicationDelegate(preview: preview)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class FocusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    private let model: DesktopModel
    private let clipboard: SystemClipboardOutput?
    private let monitor: ClipboardMonitor?
    private let shortcut = GlobalShortcut()
    private var library: NSWindow?
    private var panel: FocusPanel?
    private var statusItem: NSStatusItem?
    private var previousApp: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    private var idleTimer: Timer?
    private var captureTimer: Timer?
    private var cleanupTimer: Timer?
    private var recorder: Any?
    private let scheme: String
    private var hasLaunched = false
    private var pendingDestination: AppDestination?

    init(preview: Bool) {
        let identifier = Bundle.main.bundleIdentifier
        scheme = Bundle.main.object(forInfoDictionaryKey: "CopySaverURLScheme") as? String ?? "copysaver-dev"
        if preview {
            clipboard = nil
            monitor = nil
            model = DesktopModel(service: nil, clipboard: nil, preview: true)
        } else if let identifier,
                  let keys = try? KeychainVaultKeyProvider(bundleIdentifier: identifier),
                  let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let location = support.appendingPathComponent(identifier, isDirectory: true).appendingPathComponent("vault.sqlite")
            let output = SystemClipboardOutput(bundleIdentifier: identifier)
            clipboard = output
            monitor = ClipboardMonitor(input: SystemClipboardInput(), ownIdentifier: identifier)
            model = DesktopModel(service: DesktopVaultService(url: location, keys: keys), clipboard: output)
        } else {
            clipboard = nil
            monitor = nil
            model = DesktopModel(service: nil, clipboard: nil)
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onOpenLibrary = { [weak self] in self?.openLibrary() }
        model.onOpenFocus = { [weak self] in self?.toggleFocus() }
        model.onDismissFocus = { [weak self] in self?.dismissFocus() }
        model.onRecordShortcut = { [weak self] in self?.recordShortcut() }
        model.onRestoreShortcut = { [weak self] in self?.setShortcut(.standard) }
        model.onClearShortcut = { [weak self] in self?.clearShortcut() }
        model.onCaptureBoundary = { [weak self] in self?.monitor?.suspend() }
        model.onRequestClipboardAccess = { [weak self] in self?.monitor?.requestAccess() }
        model.onConfirmDiscardDraft = { [weak self] in self?.confirmDiscardDraft() ?? false }
        model.onWillLock = { [weak self] in
            for window in [self?.library, self?.panel].compactMap({ $0 }) {
                window.endEditing(for: nil)
                if let editor = window.fieldEditor(false, for: nil) as? NSTextView {
                    editor.string = ""; editor.undoManager?.removeAllActions()
                }
                window.undoManager?.removeAllActions()
            }
        }
        shortcut.onPress = { [weak self] in self?.toggleFocus() }
        installMenu()
        installLifecycleObservers()
        if !UserDefaults.standard.bool(forKey: "focusShortcutDisabled") {
            let saved = UserDefaults.standard.data(forKey: "focusShortcut").flatMap { try? JSONDecoder().decode(FocusShortcut.self, from: $0) }
            if let saved, saved.isValid { setShortcut(saved) } else { setShortcut(.standard) }
        } else { model.shortcutDescription = "Not set" }
        model.start()
        hasLaunched = true
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.eventID == kAEOpenApplication && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if let destination = pendingDestination { route(destination); pendingDestination = nil }
        else if !loginLaunch { openLibrary() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openLibrary(); return true }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let destination = AppDestination(url: url, scheme: scheme) else { continue }
            if hasLaunched { route(destination) } else { pendingDestination = destination }
        }
    }

    private func route(_ destination: AppDestination) {
        model.libraryQuery = ""; model.focusQuery = ""
        model.section = destination == .snippets ? .snippets : .history
        if destination == .focus { showFocus() } else { openLibrary() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.hasDirtyDraft && !confirmDiscardDraft() { return .terminateCancel }
        model.lock()
        shortcut.stop()
        cancelRecording()
        idleTimer?.invalidate()
        captureTimer?.invalidate()
        cleanupTimer?.invalidate()
        clipboard?.clearOwnedSensitiveCopy()
        return .terminateNow
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.concealSensitiveContent()
        if model.hasDirtyDraft {
            let alert = NSAlert()
            alert.messageText = "Discard this unsaved snippet?"
            alert.informativeText = "Your draft has not been saved."
            alert.addButton(withTitle: "Keep editing")
            alert.addButton(withTitle: "Discard")
            if alert.runModal() == .alertFirstButtonReturn { return false }
        }
        model.discardDraft()
        return true
    }

    @objc private func openLibrary() {
        model.isFocusPresented = false
        panel?.orderOut(nil)
        if library == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "CopySaver"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 480, height: 540)
            window.delegate = self
            window.contentView = NSHostingView(rootView: AppearanceRoot(content: LibraryView(model: model)))
            window.center()
            library = window
        }
        NSApp.activate()
        library?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleFocus() {
        if panel?.isVisible == true { dismissFocus() } else { showFocus() }
    }

    private func showFocus() {
        cancelRecording()
        model.concealSensitiveContent()
        model.isFocusPresented = true
        previousApp = NSWorkspace.shared.frontmostApplication
        if model.section != .snippets { model.section = .history }
        model.focusQuery = ""
        model.ensureSelection(query: "")
        if panel == nil {
            let panel = FocusPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.title = "CopySaver Focus"
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.delegate = self
            let root = FocusView(model: model).clipShape(RoundedRectangle(cornerRadius: 14))
            panel.contentView = NSHostingView(rootView: AppearanceRoot(content: root))
            self.panel = panel
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            panel?.setFrameOrigin(NSPoint(x: visible.midX - 320, y: visible.midY - 210))
        }
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
        model.focusActivation = UUID()
    }

    private func dismissFocus() {
        panel?.orderOut(nil)
        model.focusQuery = ""
        model.concealSensitiveContent()
        model.isFocusPresented = false
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel, !model.isBusy else { return }
        panel?.orderOut(nil)
        model.focusQuery = ""
        model.concealSensitiveContent()
        model.isFocusPresented = false
    }

    @objc private func lockVault() { model.lock() }
    @objc private func openSettings() { model.section = .settings; openLibrary() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleHistory() { model.setCaptureEnabled(!(model.settings?.captureEnabled ?? false)) }
    @objc private func togglePause() { model.toggleCapturePause() }

    private func confirmDiscardDraft() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Discard this unsaved snippet?"
        alert.informativeText = "Your draft has not been saved."
        alert.addButton(withTitle: "Keep editing"); alert.addButton(withTitle: "Discard")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        menu.removeAllItems()
        let status = NSMenuItem(title: model.captureStatus, action: nil, keyEquivalent: "")
        menu.addItem(status); menu.addItem(.separator())
        for (title, action) in [("Open Focus Mode", #selector(toggleFocus)), ("Open Library", #selector(openLibrary)),
                                (model.settings?.captureEnabled == true ? "Disable History" : "Enable History", #selector(toggleHistory)),
                                (model.settings?.manuallyPaused == true ? "Resume Capture" : "Pause Capture", #selector(togglePause)),
                                ("Settings…", #selector(openSettings)), ("Lock Vault", #selector(lockVault)), ("Quit CopySaver", #selector(quit))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: title == "Quit CopySaver" ? "q" : "")
            entry.target = self; menu.addItem(entry)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(lockVault) || menuItem.action == #selector(openSettings) { return model.phase == .unlocked }
        if menuItem.action == #selector(toggleHistory) { return model.phase == .unlocked && !model.isBusy && !model.isPreview }
        if menuItem.action == #selector(togglePause) { return model.phase == .unlocked && model.settings?.captureEnabled == true && !model.isBusy && !model.isPreview }
        return true
    }

    private func installMenu() {
        let main = NSMenu()
        let appEntry = NSMenuItem()
        let appMenu = NSMenu(title: "CopySaver")
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit CopySaver", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appEntry.submenu = appMenu
        main.addItem(appEntry)
        let editEntry = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        editEntry.submenu = edit
        main.addItem(editEntry)
        let windowEntry = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowEntry.submenu = windowMenu
        main.addItem(windowEntry)
        NSApp.mainMenu = main
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "CopySaver")
        let menu = NSMenu()
        for (title, action) in [("Open Focus Mode", #selector(toggleFocus)), ("Open Library", #selector(openLibrary)), ("Lock Vault", #selector(lockVault)), ("Quit CopySaver", #selector(quit))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: title == "Quit CopySaver" ? "q" : "")
            entry.target = self
            menu.addItem(entry)
        }
        item.menu = menu
        menu.delegate = self
        statusItem = item
    }

    private func installLifecycleObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.monitor?.rebaseline() }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.lock() }
            })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clipboard?.clearExpiredCopy() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.setPresentationActive(false)
                self?.model.focusQuery = ""
                self?.cancelRecording()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.setPresentationActive(true) }
        })
        // Supplemental lock-screen signal. The notification name is undocumented;
        // supported-OS coverage is an explicit pending M1-11 integration gate.
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.lock() }
        })
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.isPreview, self.model.phase == .unlocked,
                      let timeout = self.model.settings?.idleLockTimeout.interval,
                      let anyInput = CGEventType(rawValue: UInt32.max) else { return }
                if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) >= timeout { self.model.lock() }
            }
        }
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let monitor = self.monitor else { return }
                guard self.model.phase == .unlocked, self.model.settings?.captureEnabled == true,
                      self.model.settings?.manuallyPaused == false else { monitor.suspend(); return }
                self.model.clipboardPermission = monitor.permission
                guard !self.model.isBusy else { return }
                if let sample = monitor.poll(conditions: self.model.captureConditions, exclusions: self.model.settings?.excludedBundleIDs ?? []) {
                    self.model.capture(sample)
                }
            }
        }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.cleanupHistory() }
        }
    }

    private func setShortcut(_ value: FocusShortcut) {
        guard shortcut.replace(with: value) else {
            model.shortcutMessage = "Choose an available shortcut with Command or Control. Spotlight’s Command-Space is reserved."
            return
        }
        model.shortcutDescription = value.label
        model.shortcutMessage = nil
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "focusShortcut")
        UserDefaults.standard.set(false, forKey: "focusShortcutDisabled")
    }

    private func clearShortcut() {
        guard shortcut.clear() else { model.shortcutMessage = "The shortcut could not be cleared. Try again."; return }
        model.shortcutDescription = "Not set"
        model.shortcutMessage = nil
        UserDefaults.standard.removeObject(forKey: "focusShortcut")
        UserDefaults.standard.set(true, forKey: "focusShortcutDisabled")
    }

    private func cancelRecording() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil
        model.recordingShortcut = false
    }

    private func recordShortcut() {
        cancelRecording()
        model.recordingShortcut = true
        model.shortcutMessage = nil
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.keyCode == 53 { self.cancelRecording(); return true }
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                let name = event.keyCode == 49 ? "Space" : String((event.charactersIgnoringModifiers ?? "Key\(event.keyCode)").uppercased().prefix(16))
                let value = FocusShortcut(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue, keyName: name)
                self.cancelRecording()
                self.setShortcut(value)
                return true
            }
            return consumed ? nil : event
        }
    }
}
