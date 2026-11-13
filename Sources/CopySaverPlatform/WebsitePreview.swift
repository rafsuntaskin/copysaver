import Foundation
import ImageIO
import UniformTypeIdentifiers
import os
import Darwin

public struct WebsitePreview: Equatable, Sendable {
    public let title: String?
    public let summary: String?
    public let image: Data?
    public let host: String

    public init(title: String?, summary: String?, image: Data?, host: String) {
        self.title = title; self.summary = summary; self.image = image; self.host = host
    }
}

public protocol WebsitePreviewLoading: Sendable {
    func load(_ url: URL) async throws -> WebsitePreview
}

public enum WebsitePreviewFailure: Error { case unsupportedURL, unavailable, oversized, cancelled }

/// No cookies, credentials, persistent cache, web view, scripts, or diagnostics.
public struct HTTPWebsitePreviewLoader: WebsitePreviewLoading {
    private let sessionFactory: @Sendable (URLSessionConfiguration) -> URLSession
    private let publicAddressCheck: @Sendable (URL) async -> Bool
    public init() {
        sessionFactory = { URLSession(configuration: $0) }
        publicAddressCheck = { await WebsitePreviewURLPolicy.resolvesPublicly($0) }
    }
    init(sessionFactory: @escaping @Sendable (URLSessionConfiguration) -> URLSession,
         publicAddressCheck: @escaping @Sendable (URL) async -> Bool) {
        self.sessionFactory = sessionFactory; self.publicAddressCheck = publicAddressCheck
    }
    public static func supports(_ url: URL) -> Bool { WebsitePreviewURLPolicy.allows(url) }

    public func load(_ url: URL) async throws -> WebsitePreview {
        guard WebsitePreviewURLPolicy.allows(url) else { throw WebsitePreviewFailure.unsupportedURL }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = sessionFactory(configuration)
        defer { session.invalidateAndCancel() }
        let (data, finalURL) = try await fetch(url, session: session, limit: 262_144, image: false)
        let html = String(decoding: data, as: UTF8.self)
        let metadata = WebsiteMetadata.parse(html, baseURL: finalURL)
        var thumbnail: Data?
        if let imageURL = metadata.imageURL {
            // A missing/unsupported image must not discard usable page metadata.
            if let (bytes, _) = try? await fetch(imageURL, session: session, limit: 1_048_576, image: true) {
                thumbnail = Self.thumbnail(bytes)
            }
        }
        try Task.checkCancellation()
        guard metadata.title != nil || metadata.summary != nil || thumbnail != nil else { throw WebsitePreviewFailure.unavailable }
        return WebsitePreview(title: metadata.title, summary: metadata.summary, image: thumbnail, host: finalURL.host() ?? "")
    }

    private func fetch(_ url: URL, session: URLSession, limit: Int, image: Bool) async throws -> (Data, URL) {
        guard WebsitePreviewURLPolicy.allows(url), await publicAddressCheck(url) else {
            throw WebsitePreviewFailure.unsupportedURL
        }
        try Task.checkCancellation()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpShouldHandleCookies = false
        request.setValue(image ? "image/png,image/jpeg,image/webp,image/gif" : "text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let delegate = PreviewRequestDelegate()
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              let finalURL = response.url, WebsitePreviewURLPolicy.allows(finalURL) else { throw WebsitePreviewFailure.unavailable }
        let mime = response.mimeType?.lowercased() ?? ""
        let accepted = image ? ["image/png", "image/jpeg", "image/webp", "image/gif"].contains(mime) : ["text/html", "application/xhtml+xml"].contains(mime)
        guard accepted else { throw WebsitePreviewFailure.unavailable }
        guard !image || response.expectedContentLength <= Int64(limit) else { throw WebsitePreviewFailure.oversized }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else {
                if image { throw WebsitePreviewFailure.oversized }
                break // Metadata in a bounded head prefix still works for large pages.
            }
            data.append(byte)
            if !image, byte == 62, String(decoding: data.suffix(7), as: UTF8.self).lowercased() == "</head>" { break }
        }
        return (data, finalURL)
    }

    static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8_192, height <= 8_192, width * height <= 8_388_608,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 1_048_576 else { return nil }
        return output as Data
    }
}

struct WebsiteMetadata: Equatable {
    let title: String?
    let summary: String?
    let imageURL: URL?

    static func parse(_ html: String, baseURL: URL) -> Self {
        // Bounded input, literal text extraction only. Never hand HTML to a renderer.
        let source = String(html.prefix(262_144))
            .replacingOccurrences(of: #"(?is)<!--.*?-->|<script\b[^>]*>.*?</script\s*>|<style\b[^>]*>.*?</style\s*>"#, with: "", options: .regularExpression)
        var fields: [String: String] = [:]
        if let tags = try? NSRegularExpression(pattern: #"(?is)<meta\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>"#),
           let attributes = try? NSRegularExpression(pattern: #"(?is)([a-z_:][a-z0-9_:.-]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#) {
            let text = source as NSString
            for match in tags.matches(in: source, range: NSRange(location: 0, length: text.length)).prefix(128) where match.range.length <= 8_192 {
                let tag = text.substring(with: match.range) as NSString
                var values: [String: String] = [:]
                for attribute in attributes.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                    let key = tag.substring(with: attribute.range(at: 1)).lowercased()
                    if let range = (2...4).map({ attribute.range(at: $0) }).first(where: { $0.location != NSNotFound }) {
                        values[key] = tag.substring(with: range)
                    }
                }
                if let key = values["property"] ?? values["name"], let content = values["content"], fields[key.lowercased()] == nil {
                    fields[key.lowercased()] = content
                }
            }
        }
        let titleMatch = source.range(of: #"(?is)<title\b[^>]*>(.*?)</title\s*>"#, options: .regularExpression)
        let fallbackTitle = titleMatch.map { String(source[$0]).replacingOccurrences(of: #"(?is)</?title\b[^>]*>"#, with: "", options: .regularExpression) }
        let title = clean(fields["og:title"] ?? fields["twitter:title"] ?? fallbackTitle, limit: 200)
        let summary = clean(fields["og:description"] ?? fields["twitter:description"] ?? fields["description"], limit: 400)
        let imageText = (fields["og:image:secure_url"] ?? fields["og:image"] ?? fields["twitter:image"]).map(decodeEntities)
        let imageURL = imageText.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }.flatMap { WebsitePreviewURLPolicy.allows($0) ? $0 : nil }
        return Self(title: title, summary: summary, imageURL: imageURL)
    }

    private static func clean(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let decoded = decodeEntities(value).unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }
        let text = String(String.UnicodeScalarView(decoded)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : String(text.prefix(limit))
    }

    static func decodeEntities(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]{1,8}|#[0-9]{1,8}|amp|quot|apos|lt|gt|nbsp);"#) else { return text }
        let source = text as NSString
        var result = text
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let token = source.substring(with: match.range(at: 1))
            let named = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " "]
            var replacement = named[token]
            if token.hasPrefix("#") {
                let hex = token.hasPrefix("#x")
                if let value = UInt32(token.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(value) { replacement = String(scalar) }
            }
            if let replacement, let range = Range(match.range, in: result) { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }
}

struct WebsitePreviewURLPolicy {
    static func allows(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= 8_192, url.scheme?.lowercased() == "https",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = url.host(percentEncoded: true)?.lowercased(), host.contains("."), !host.hasSuffix("."),
              !host.contains(":"), !host.contains("%"), !host.allSatisfy({ $0.isNumber || $0 == "." }),
              !["localhost", "local", "internal", "lan", "home", "test", "invalid", "onion"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }
        return true
    }

    static func isPublicIPv4(_ value: UInt32) -> Bool {
        let a = value >> 24, b = (value >> 16) & 255, c = (value >> 8) & 255
        return !([0, 10, 127].contains(a) || a >= 224 || a == 169 && b == 254 ||
            a == 172 && (16...31).contains(b) || a == 192 && (b == 168 || b == 0 || b == 88 && c == 99) ||
            a == 100 && (64...127).contains(b) || a == 198 && (b == 18 || b == 19 || b == 51 && c == 100) ||
            a == 203 && b == 0 && c == 113)
    }

    static func resolvesPublicly(_ url: URL) async -> Bool {
        guard let host = url.host() else { return false }
        // The system resolver may finish after cancellation; no HTTP request may
        // start until it returns and the caller rechecks cancellation.
        return await Task.detached(priority: .utility) {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return false }
            defer { freeaddrinfo(first) }
            var next: UnsafeMutablePointer<addrinfo>? = first
            while let item = next {
                if item.pointee.ai_family == AF_INET, let address = item.pointee.ai_addr {
                    let value = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
                    if !isPublicIPv4(value) { return false }
                } else if item.pointee.ai_family == AF_INET6, let address = item.pointee.ai_addr {
                    let value = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                    let bytes = withUnsafeBytes(of: value) { Array($0) }
                    // Accept global-unicast IPv6 only; mapped/loopback/link-local
                    // and unique-local addresses are deliberately excluded.
                    if bytes[0] & 0xe0 != 0x20 || bytes.prefix(4).elementsEqual([0x20, 0x01, 0x0d, 0xb8]) { return false }
                } else { return false }
                next = item.pointee.ai_next
            }
            return true
        }.value
    }
}

private final class PreviewRequestDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let redirects = OSAllocatedUnfairLock(initialState: 0)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        let permitted = redirects.withLock { count in count += 1; return count <= 3 }
        guard permitted, let url = request.url, WebsitePreviewURLPolicy.allows(url), await WebsitePreviewURLPolicy.resolvesPublicly(url), !Task.isCancelled else { return nil }
        return request
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? (.performDefaultHandling, nil) : (.cancelAuthenticationChallenge, nil)
    }
}
