import Foundation
import Testing
@testable import CopySaverDomain

@Test func contentPreviewRecognizesOnlyExplicitSafeWebLinks() throws {
    let original = "  https://example.com/a%20path?secret=synthetic#fragment\n"
    guard case .webLink(let link) = TextContentPreview.classify(original) else { Issue.record("Missing web preview"); return }
    #expect(link.host == "example.com")
    #expect(link.path == "/a%20path")
    #expect(link.url.absoluteString == "https://example.com/a%20path?secret=synthetic#fragment")
    guard case .webLink(let www) = TextContentPreview.classify("www.example.com/docs") else { Issue.record("Missing www preview"); return }
    #expect(www.url.scheme == "https")
    for value in ["javascript:alert(1)", "file:///tmp/example", "data:text/html,hello", "copysaver://focus", "https://trusted.example@other.example/", "https://user:password@example.com", "https://", "https://example.com:99999", "https://example.com/\nhttps://other.example", "Please visit https://example.com", "https://example.com/\u{202E}example"] {
        #expect(TextContentPreview.classify(value) == .text)
    }
    guard case .webLink(let idn) = TextContentPreview.classify("https://日本語.example/path") else { Issue.record("Missing international link preview"); return }
    #expect(idn.host.contains("xn--"))
}

@Test func contentPreviewFormatsJSONWithoutChangingTokens() throws {
    let value = #"{"large":9007199254740993,"decimal":1.2300e+03,"escaped":"a\nb\"c","empty":[],"nested":[true,{"日本語":"café"}]}"#
    guard case .json(let formatted) = TextContentPreview.classify(value) else { Issue.record("Missing JSON preview"); return }
    #expect(formatted.contains("9007199254740993"))
    #expect(formatted.contains("1.2300e+03"))
    #expect(formatted.contains(#""a\nb\"c""#))
    #expect(formatted.contains("\n  \"large\""))
    #expect(formatted.contains("\"empty\": []"))
    let original = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? NSDictionary
    let preview = try JSONSerialization.jsonObject(with: Data(formatted.utf8)) as? NSDictionary
    #expect(original == preview)
    for value in ["{invalid}", "[1,]", "42", "true", #""text""#] {
        #expect(TextContentPreview.classify(value) == .text)
    }
}

@Test func contentPreviewHandlesContactsCodeAndOrdinaryText() {
    #expect(TextContentPreview.classify("hello@example.com") == .email("hello@example.com"))
    #expect(TextContentPreview.classify("+1 (202) 555-0100") == .phone("+1 (202) 555-0100"))
    #expect(TextContentPreview.classify("```swift\nlet sample = 1\n```") == .code(language: "swift", body: "let sample = 1"))
    #expect(TextContentPreview.classify("```\n  café 日本語  \n```") == .code(language: nil, body: "  café 日本語  "))
    #expect(TextContentPreview.classify("def greet():\n    return 'hello'") == .code(language: "Python", body: "def greet():\n    return 'hello'"))
    for value in ["Alex Example\n123 Example Street", "Hello **world**", "let me know\nwhen you are ready", "2026-11-12", "1234567890", "invalid@@example.com", "```swift\nunclosed", "<script>alert('sample')</script>", "=SUM(A1:A2)"] {
        #expect(TextContentPreview.classify(value) == .text)
    }
}

@Test func contentPreviewBoundsWorkAndFormattedOutput() {
    let huge = "https://example.com/" + String(repeating: "a", count: TextContentPreview.maximumAnalysisBytes)
    #expect(TextContentPreview.classify(huge) == .text)
    let deep = String(repeating: "[", count: 100) + "1" + String(repeating: "]", count: 100)
    #expect(TextContentPreview.classify(deep) == .text)
    #expect(TextContentPreview.classify("") == .text)
    #expect(TextContentPreview.classify(" \n\t") == .text)
}
