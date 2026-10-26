import Foundation

public enum AppDestination: String, CaseIterable, Sendable {
    case focus, history, snippets

    public init?(url: URL, scheme: String) {
        guard let candidate = Self.allCases.first(where: { url.absoluteString == "\(scheme)://\($0.rawValue)" }) else {
            return nil
        }
        self = candidate
    }
}
