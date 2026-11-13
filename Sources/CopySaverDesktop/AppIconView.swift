import AppKit
import SwiftUI

/// Public brand artwork only. Never loads user content or remote resources.
struct AppIconView: View {
    var size: CGFloat = 32
    private static let icon: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        Group {
            if let image = Self.icon {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "square.on.square").resizable().scaledToFit().padding(5)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
