import Foundation

/// Ephemeral presentation only. Never persisted, fetched, executed, or used as copy output.
public enum TextContentPreview: Equatable, Sendable {
    case text
    case webLink(WebLinkPreview)
    case email(String)
    case phone(String)
    case json(formatted: String)
    case code(language: String?, body: String)

    public static let maximumAnalysisBytes = 16_384

    public static func classify(_ original: String) -> Self {
        // Analyze the complete value or fall back. Never misclassify a truncated prefix.
        guard original.utf8.count <= maximumAnalysisBytes else { return .text }
        let value = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .text }
        if let link = WebLinkPreview(text: value) { return .webLink(link) }
        if value.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$"#, options: .regularExpression) != nil {
            return .email(value)
        }
        if value.range(of: #"^\+?[0-9][0-9 ()\-.]{5,28}[0-9]$"#, options: .regularExpression) != nil {
            let digits = value.filter(\.isNumber).count
            // A phone preview is a hint, not validation or a payment-card detector.
            if (7...15).contains(digits),
               value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) == nil,
               value.hasPrefix("+") || value.contains("(") || value.contains("-") {
                return .phone(value)
            }
        }
        if (value.hasPrefix("{") || value.hasPrefix("[")),
           (try? JSONSerialization.jsonObject(with: Data(value.utf8))) != nil,
           let formatted = formattedJSON(value) {
            return .json(formatted: formatted)
        }
        let lines = value.components(separatedBy: .newlines)
        if lines.count >= 3, let first = lines.first, first.hasPrefix("```"), lines.last == "```" {
            let language = String(first.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if language.isEmpty || language.range(of: #"^[A-Za-z0-9_+#.-]{1,24}$"#, options: .regularExpression) != nil {
                return .code(language: language.isEmpty ? nil : language, body: lines.dropFirst().dropLast().joined(separator: "\n"))
            }
        }
        if lines.count >= 2 {
            if value.hasPrefix("import SwiftUI") || value.hasPrefix("import Foundation") || value.hasPrefix("func ") {
                return .code(language: "Swift", body: original)
            }
            if value.range(of: #"^(?:(?:const|let|var)\s+[A-Za-z_$][A-Za-z0-9_$]*\s*(?:=|:)|(?:export\s+)?function\s+[A-Za-z_$][A-Za-z0-9_$]*\s*\()"#, options: .regularExpression) != nil {
                return .code(language: nil, body: original)
            }
            if value.hasPrefix("def ") || value.hasPrefix("from ") && value.contains(" import ") {
                return .code(language: "Python", body: original)
            }
            if value.hasPrefix("#!/bin/") || value.hasPrefix("#!/usr/bin/env ") {
                return .code(language: "Shell", body: original)
            }
        }
        return .text
    }

    /// Formatting preserves token spelling, key order, large numbers and escapes.
    /// JSONSerialization validates first, but reserialization could change these values.
    private static func formattedJSON(_ value: String) -> String? {
        var output = ""
        var depth = 0
        var inString = false
        var escaped = false
        var previous: Character?
        for character in value {
            guard depth <= 32, output.utf8.count <= 65_536 else { return nil }
            if inString {
                output.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            if character.isWhitespace { continue }
            switch character {
            case "\"":
                if previous == "{" || previous == "[" { output += "\n" + String(repeating: "  ", count: depth) }
                inString = true; output.append(character)
            case "{", "[":
                if previous == "{" || previous == "[" { output += "\n" + String(repeating: "  ", count: depth) }
                output.append(character); depth += 1
            case "}", "]":
                // Foundation accepts trailing commas on some supported systems.
                guard previous != "," else { return nil }
                depth -= 1
                if previous != "{" && previous != "[" { output += "\n" + String(repeating: "  ", count: depth) }
                output.append(character)
            case ",": output += ",\n" + String(repeating: "  ", count: depth)
            case ":": output += ": "
            default:
                if previous == "{" || previous == "[" { output += "\n" + String(repeating: "  ", count: depth) }
                output.append(character)
            }
            previous = character
        }
        return output
    }
}

public struct WebLinkPreview: Equatable, Sendable {
    public let url: URL
    /// The actual ASCII/punycode host. Never a fabricated page title.
    public let host: String
    public let path: String

    public init?(text: String) {
        guard text.utf8.count <= 8_192,
              !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              text.range(of: #"[\u202A-\u202E\u2066-\u2069]"#, options: .regularExpression) == nil else { return nil }
        let candidate = text.lowercased().hasPrefix("www.") ? "https://" + text : text
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              components.user == nil, components.password == nil,
              let url = components.url, let host = url.host(percentEncoded: true), !host.isEmpty,
              host != ".", !host.contains("%"), components.port.map({ (1...65_535).contains($0) }) ?? true else { return nil }
        self.url = url
        self.host = host
        // Path stays encoded so control characters/RTL escapes cannot disguise the host.
        self.path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    }
}
