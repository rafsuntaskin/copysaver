import AppKit
import CopySaverDomain
import SwiftUI

extension TextContentPreview {
    var label: String {
        switch self {
        case .text: "Plain text"
        case .webLink: "Link"
        case .email: "Email address"
        case .phone: "Phone number"
        case .json: "JSON"
        case .code(let language, _): language.map { "\($0) code" } ?? "Code"
        }
    }
    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .webLink: "link"
        case .email: "envelope"
        case .phone: "phone"
        case .json: "curlybraces"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
    var rowTitle: String? {
        if case .webLink(let link) = self { return link.host }
        return nil
    }
    var rowSummary: String? {
        switch self {
        case .webLink(let link): link.path
        case .json: "Structured data"
        case .code(let language, _): language ?? "Code"
        case .email: "Email address"
        case .phone: "Phone number"
        case .text: nil
        }
    }
}

/// Local-only presentation of a nonsensitive selection. The original remains
/// available and all text copying goes through the existing ownership policy.
struct ContentPreviewView: View {
    let preview: TextContentPreview
    let original: String
    var canOpenLink = true
    let copy: @MainActor (String, @escaping @MainActor () -> Void) -> Void
    @State private var showOriginal = false
    @State private var openFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch preview {
            case .webLink(let link):
                linkPreview(link)
                originalLabel
                textView(original)
            case .email(let address):
                contactPreview(address, title: "Email address", symbol: "envelope")
                originalLabel
                textView(original)
            case .phone(let number):
                contactPreview(number, title: "Phone number", symbol: "phone")
                originalLabel
                textView(original)
            case .json(let formatted):
                formatPicker(previewTitle: "Formatted JSON")
                textView(showOriginal ? original : formatted)
            case .code(let language, let body):
                formatPicker(previewTitle: language.map { "\($0) preview" } ?? "Code preview")
                textView(showOriginal ? original : body)
            case .text:
                textView(original)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: original) { _, _ in showOriginal = false; openFailed = false }
    }

    private var originalLabel: some View {
        Text("SAVED TEXT").font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
    }

    private func textView(_ value: String) -> some View {
        VaultTextEditor(text: .constant(value), editable: false, accessibilityName: showOriginal ? "Original saved text" : "Saved text preview", copy: copy)
    }

    private func formatPicker(previewTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Text display", selection: $showOriginal) {
                Text(previewTitle).tag(false)
                Text("Original").tag(true)
            }.pickerStyle(.segmented).fixedSize(horizontal: false, vertical: true)
            Text("The Copy button keeps the original saved text.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func linkPreview(_ link: WebLinkPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "globe").font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
                    .frame(width: 42, height: 42).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: link.host).font(.system(size: 19, weight: .semibold)).lineLimit(2)
                    Text(verbatim: link.path).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .center) {
                Text("Local preview").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    // Only validated HTTP(S) URLs reach this explicit user action.
                    openFailed = !NSWorkspace.shared.open(link.url)
                } label: { Label("Open in browser", systemImage: "arrow.up.right") }
                    .buttonStyle(.bordered).controlSize(.small).disabled(!canOpenLink)
                    .help("Opens the full saved URL in your browser")
            }
            if openFailed { Text("The browser could not open this link.").font(.caption).foregroundStyle(.secondary).accessibilityLabel("The browser could not open this link") }
        }.padding(18)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
    }

    private func contactPreview(_ value: String, title: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(.secondary).frame(width: 32)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(verbatim: value).font(.system(size: 19, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18).background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
