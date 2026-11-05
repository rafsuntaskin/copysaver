import SwiftUI

struct KeyboardHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary).padding(.horizontal, 5).padding(.vertical, 3)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
    }
}

/// Shared native text field, with a stable clear action and an explicit focus ring.
struct LibrarySearchField: View {
    @Binding var text: String
    let prompt: String
    let focus: FocusState<Bool>.Binding
    var prominent = false
    var hint: String?
    var submit: () -> Void = {}
    var move: ((Int) -> Void)?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: prominent ? 18 : 13)).foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain)
                .font(.system(size: prominent ? 19 : 13)).focused(focus).accessibilityLabel(prompt)
                .onSubmit(submit)
                .onKeyPress(.downArrow) { guard let move else { return .ignored }; move(1); return .handled }
                .onKeyPress(.upArrow) { guard let move else { return .ignored }; move(-1); return .handled }
            if !text.isEmpty {
                Button { text = ""; focus.wrappedValue = true } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear search").accessibilityLabel("Clear search")
            }
            if let hint { KeyboardHint(hint) }
        }
        .padding(.horizontal, prominent ? 14 : 11).padding(.vertical, prominent ? 14 : 10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: prominent ? 12 : 8))
        .overlay {
            RoundedRectangle(cornerRadius: prominent ? 12 : 8)
                .strokeBorder(focus.wrappedValue ? Color.accentColor.opacity(0.7) : Color(nsColor: .separatorColor).opacity(contrast == .increased ? 1 : 0.6), lineWidth: focus.wrappedValue ? 2 : 1)
        }
    }
}
