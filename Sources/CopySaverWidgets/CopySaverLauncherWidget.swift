import Foundation
import SwiftUI
import WidgetKit

public enum LauncherDestination: String, CaseIterable, Sendable {
    case focus, history, snippets
    public func url(development: Bool, community: Bool = false) -> URL {
        // Both components are compile-time allowlists; no user data enters a URL.
        let scheme = community ? (development ? "copysaver-community-dev" : "copysaver-community") : (development ? "copysaver-dev" : "copysaver")
        return URL(string: "\(scheme)://\(rawValue)")!
    }
}

private struct LauncherEntry: TimelineEntry { let date: Date }
private struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry { LauncherEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) { completion(LauncherEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: Date())], policy: .never))
    }
}

public struct CopySaverLauncherWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "org.copysaver.launcher", provider: LauncherProvider()) { _ in LauncherView() }
            .configurationDisplayName("CopySaver")
            .description("Open your local clipboard library or named snippets.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct LauncherView: View {
    @Environment(\.widgetFamily) private var family
    private var development: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
    private func url(_ destination: LauncherDestination) -> URL {
        destination.url(development: development, community: Bundle.main.object(forInfoDictionaryKey: "CopySaverCommunityBuild") as? Bool == true)
    }
    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("CopySaver", systemImage: "clipboard").font(.headline)
                Text("Clipboard & snippets").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if family == .systemMedium {
                    Link(destination: url(.focus)) { focusLabel }
                } else { focusLabel }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if family == .systemMedium {
                Divider()
                VStack(alignment: .leading, spacing: 20) {
                    Link(destination: url(.history)) { Label("History", systemImage: "clock") }
                    Link(destination: url(.snippets)) { Label("Snippets", systemImage: "doc.text") }
                }.font(.system(size: 13)).frame(width: 100, alignment: .leading)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(url(.focus))
    }
    private var focusLabel: some View {
        Label("Open Focus Mode", systemImage: "magnifyingglass")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
    }
}
