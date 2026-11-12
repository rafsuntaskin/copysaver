import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Testing
@testable import CopySaverPlatform

@Test func websitePreviewParsesPageMetadataWithoutRenderingHTML() throws {
    let base = try #require(URL(string: "https://example.com/docs/page"))
    let html = """
    <html><head><title>Fallback</title>
    <!-- <meta property='og:title' content='Comment'> -->
    <script>const fake = "<meta property='og:title' content='Script'>";</script>
    <meta content="Synthetic &amp; &#x65E5;&#26412;" property="og:title">
    <meta property='og:title' content='Second'>
    <meta name='description' content='Fallback description'>
    <meta content='A short &quot;description&quot;.' property='og:description'>
    <meta property=og:image content='/preview.png?x=1&amp;y=2'>
    </head></html>
    """
    let value = WebsiteMetadata.parse(html, baseURL: base)
    #expect(value.title == "Synthetic & 日本")
    #expect(value.summary == "A short \"description\".")
    #expect(value.imageURL?.absoluteString == "https://example.com/preview.png?x=1&y=2")
    let fallback = WebsiteMetadata.parse("<title>  Exact &lt;literal&gt; title  </title><meta name=description content='A description'>", baseURL: base)
    #expect(fallback.title == "Exact <literal> title")
    #expect(fallback.summary == "A description")
    let blocked = WebsiteMetadata.parse("<meta property='og:image' content='file:///tmp/example.png'>", baseURL: base)
    #expect(blocked.imageURL == nil)
}

@Test func websitePreviewRejectsUnsafeDestinationsAndPrivateAddresses() throws {
    for value in ["http://example.com", "https://127.0.0.1", "https://[::1]", "https://localhost", "https://host.local", "https://host.internal", "https://example.com:8443", "https://user:secret@example.com", "file:///tmp/example", "data:text/html,sample"] {
        #expect(!WebsitePreviewURLPolicy.allows(try #require(URL(string: value))))
    }
    #expect(WebsitePreviewURLPolicy.allows(try #require(URL(string: "https://example.com/path?sample=1"))))
    for ip: UInt32 in [0x00000000, 0x0a000001, 0x7f000001, 0xa9fe0001, 0xac100001, 0xc0a80001, 0x64400001, 0xc6120001, 0xc0000201, 0xcb007101, 0xe0000001] {
        #expect(!WebsitePreviewURLPolicy.isPublicIPv4(ip))
    }
    #expect(WebsitePreviewURLPolicy.isPublicIPv4(0x08080808))
}

private final class PreviewFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "example.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let body: Data
        let mime: String
        switch url.path {
        case "/large-html": body = Data(("<title>Large page</title>" + String(repeating: " ", count: 300_000)).utf8); mime = "text/html"
        case "/oversized": body = Data(repeating: 32, count: 262_145); mime = "text/html"
        case "/wrong-type": body = Data("not HTML".utf8); mime = "application/json"
        case "/empty": body = Data("<html><body>No metadata</body></html>".utf8); mime = "text/html"
        default: body = Data("<title>Synthetic page</title><meta name='description' content='Exact synthetic description'>".utf8); mime = "text/html"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func websitePreviewHTTPUsesEphemeralBoundedTransport() async throws {
    let loader = HTTPWebsitePreviewLoader(sessionFactory: { configuration in
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        configuration.protocolClasses = [PreviewFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }, publicAddressCheck: { _ in true })
    let value = try await loader.load(try #require(URL(string: "https://example.com/page")))
    #expect(value.title == "Synthetic page" && value.summary == "Exact synthetic description" && value.image == nil)
    let large = try await loader.load(try #require(URL(string: "https://example.com/large-html")))
    #expect(large.title == "Large page")
    for path in ["oversized", "wrong-type", "empty"] {
        await #expect(throws: (any Error).self) { try await loader.load(try #require(URL(string: "https://example.com/" + path))) }
    }
}

@Test func websitePreviewImageIsBoundedAndReencodedWithoutMetadata() throws {
    #expect(HTTPWebsitePreviewLoader.thumbnail(Data("not an image".utf8)) == nil)
    let context = try #require(CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
    let image = try #require(context.makeImage())
    let bytes = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "synthetic metadata"]] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let thumbnail = try #require(HTTPWebsitePreviewLoader.thumbnail(bytes as Data))
    let source = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == 640)
    #expect(properties[kCGImagePropertyPixelHeight] as? Int == 320)
    #expect((properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyPNGDescription] == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COPY_SAVER_WEB_SMOKE"] == "1"))
func websitePreviewPublicWebsiteSmoke() async throws {
    // Fixed public documentation site only. Never accepts a user URL or vault input.
    let preview = try await HTTPWebsitePreviewLoader().load(try #require(URL(string: "https://ogp.me/")))
    #expect(preview.title?.isEmpty == false)
    #expect(preview.image != nil)
    print("Public documentation website title and preview image loaded successfully.")
}
