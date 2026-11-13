import SwiftUI

/// Selection belongs to navigation state; pointer and keyboard feedback stay local
/// to a fixed row, without native plain-button dimming or layout animation.
struct SidebarButtonStyle: ButtonStyle {
    var selected = false
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 10
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.copySaverWindowIsKey) private var windowIsKey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .padding(.horizontal, horizontalPadding).padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .foregroundStyle(Color.primary.opacity(enabled ? 1 : 0.4))
            .background {
                SidebarRowSurface(selected: selected, hovered: hovered && enabled && windowIsKey,
                                  pressed: configuration.isPressed && enabled && windowIsKey,
                                  focused: focused && enabled, increasedContrast: contrast == .increased)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
            .onChange(of: windowIsKey) { _, isKey in if !isKey { hovered = false } }
            .focusEffectDisabled()
    }
}

struct SidebarRowSurface: View {
    var selected = false
    var hovered = false
    var pressed = false
    var focused = false
    var increasedContrast = false
    @Environment(\.copySaverWindowIsKey) private var windowIsKey

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        let keyboardFocused = focused && windowIsKey
        ZStack {
            shape.fill(selected ? Color.accentColor.opacity(increasedContrast ? 0.22 : 0.13) : .clear)
            shape.fill(Color.primary.opacity(pressed ? 0.09 : hovered ? 0.045 : 0))
            shape.strokeBorder(keyboardFocused ? Color.accentColor : increasedContrast && selected ? Color.accentColor.opacity(0.6) : .clear,
                               lineWidth: keyboardFocused ? 2 : 1)
        }
    }
}

struct SidebarRowLabel: View {
    let title: String
    let symbol: String
    var shortcut: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 20)
            Text(title)
            Spacer(minLength: 4)
            if let shortcut { Text(shortcut).font(.system(size: 10)).foregroundStyle(.tertiary).accessibilityHidden(true) }
        }
    }
}

struct CaptureStatusView: View {
    var model: DesktopModel

    private var symbol: String {
        if model.isPreview { return "eye" }
        switch model.captureConditions.availability {
        case .ready: return "record.circle"
        case .paused: return "pause.circle"
        case .disabled: return "minus.circle"
        case .permissionNeeded: return "exclamationmark.circle"
        case .storageUnavailable: return "externaldrive.badge.exclamationmark"
        case .locked: return model.automaticallyOpensVault ? "pause.circle" : "lock"
        }
    }
    private var color: Color {
        switch model.captureConditions.availability {
        case .ready: return model.isPreview ? .secondary : .green
        case .permissionNeeded, .storageUnavailable: return .orange
        default: return .secondary
        }
    }
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(model.captureStatus).foregroundStyle(.secondary)
        }.font(.system(size: 12)).accessibilityElement(children: .combine)
    }
}
