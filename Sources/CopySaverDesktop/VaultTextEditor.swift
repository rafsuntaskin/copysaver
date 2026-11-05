import AppKit
import SwiftUI

/// Routes body copy/cut through the app's ownership and authentication policy.
/// Disables text dragging/services and private framework editing history.
struct VaultTextEditor: NSViewRepresentable {
    @Binding var text: String
    var editable = true
    var accessibilityName = "Snippet text"
    let copy: @MainActor (String, @escaping @MainActor () -> Void) -> Void
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        let editor = PolicyTextView(frame: textView.frame)
        editor.drawsBackground = false
        editor.textColor = .labelColor
        editor.isRichText = false; editor.importsGraphics = false; editor.allowsUndo = true
        editor.isAutomaticDataDetectionEnabled = false; editor.isAutomaticLinkDetectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false; editor.isGrammarCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false; editor.isAutomaticTextReplacementEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel(accessibilityName)
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PolicyTextView else { return }
        if editor.string != text || !editor.string.utf8.elementsEqual(text.utf8) { editor.string = text }
        editor.isEditable = enabled && editable
        editor.copySelection = { [weak editor] value, range, cut in
            guard let editor else { return }
            let expected = editor.string
            copy(value) { [weak editor] in
                guard cut, let editor, editor.selectedRange() == range,
                      editor.string.utf8.elementsEqual(expected.utf8), editor.isEditable,
                      editor.shouldChangeText(in: range, replacementString: "") else { return }
                editor.insertText("", replacementRange: range)
            }
        }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? PolicyTextView else { return }
        editor.delegate = nil; editor.copySelection = nil; editor.string = ""; editor.undoManager?.removeAllActions()
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: VaultTextEditor
        init(_ parent: VaultTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let editor = notification.object as? NSTextView { parent.text = editor.string } }
    }
}

@MainActor private final class PolicyTextView: NSTextView {
    private let localUndo = UndoManager()
    override var undoManager: UndoManager? { localUndo }
    var copySelection: ((String, NSRange, Bool) -> Void)?
    override func copy(_ sender: Any?) { requestCopy(cut: false) }
    override func cut(_ sender: Any?) { requestCopy(cut: true) }
    private func requestCopy(cut: Bool) {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else { return }
        copySelection?((string as NSString).substring(with: range), range, cut)
    }
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool { false }
    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? { nil }
    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [] }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [("Cut", #selector(cut(_:))), ("Copy", #selector(copy(_:))), ("Paste", #selector(paste(_:))), ("Select All", #selector(selectAll(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        return menu
    }
}
