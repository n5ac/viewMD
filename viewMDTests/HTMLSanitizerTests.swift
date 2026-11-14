//
//  HTMLSanitizerTests.swift
//  viewMDTests
//
//  Unit tests for HTMLSanitizer and URLPolicy (REQ-007, REQ-022).
//

import Foundation
import Testing
@testable import viewMD

@Suite("HTMLSanitizer")
struct HTMLSanitizerTests {

    @Test("HTML without tags is returned unchanged")
    func plainText() {
        #expect(HTMLSanitizer.sanitize("a & b > c") == "a & b > c")
    }

    @Test("Safe tags and attributes pass through", arguments: [
        "<details open><summary>S</summary></details>",
        "<kbd>⌘</kbd>",
        "<img src=\"a.png\" alt=\"x\" width=\"10\" />",
        "<a href=\"https://e.com\" title='t'>x</a>",
        "<p align=center>x</p>",
        "<br>",
    ])
    func safeHTMLKept(html: String) {
        #expect(HTMLSanitizer.sanitize(html) == html)
    }

    @Test("Filtered tags have their < escaped, in any case, open or closing", arguments: [
        ("<script>alert(1)</script>", "&lt;script>alert(1)&lt;/script>"),
        ("<SCRIPT src=x></SCRIPT>", "&lt;SCRIPT src=x>&lt;/SCRIPT>"),
        ("<iframe src=\"https://e.com\"></iframe>", "&lt;iframe src=\"https://e.com\">&lt;/iframe>"),
        ("<style>body{}</style>", "&lt;style>body{}&lt;/style>"),
        ("<object data=x>", "&lt;object data=x>"),
        ("<meta http-equiv=refresh content=0>", "&lt;meta http-equiv=refresh content=0>"),
        ("<base href=\"https://evil\">", "&lt;base href=\"https://evil\">"),
    ])
    func tagFilter(html: String, expected: String) {
        #expect(HTMLSanitizer.sanitize(html) == expected)
    }

    @Test("Similar tag names aren't filtered")
    func tagFilterIsExact() {
        #expect(HTMLSanitizer.sanitize("<scripts>") == "<scripts>")
        #expect(HTMLSanitizer.sanitize("<linkage>") == "<linkage>")
    }

    @Test("Event-handler attributes are removed", arguments: [
        ("<img src=a.png onerror=\"alert(1)\">", "<img src=a.png>"),
        ("<div ONCLICK='x()' class=\"c\">", "<div class=\"c\">"),
        ("<b onmouseover=alert(1)>x</b>", "<b>x</b>"),
        ("<img onerror=\"a('>')\" src=x />", "<img src=x />"),
    ])
    func eventHandlersRemoved(html: String, expected: String) {
        #expect(HTMLSanitizer.sanitize(html) == expected)
    }

    @Test("Script URLs are removed from URL attributes", arguments: [
        ("<a href=\"javascript:alert(1)\">x</a>", "<a>x</a>"),
        ("<a href=\"JaVaScRiPt:alert(1)\">x</a>", "<a>x</a>"),
        ("<a href=\"java&#x09;script:alert(1)\">x</a>", "<a>x</a>"),
        ("<a href=\"javascript&colon;alert(1)\">x</a>", "<a>x</a>"),
        ("<a href=\" javascript:alert(1)\">x</a>", "<a>x</a>"),
        ("<a href=\"&#106;avascript:alert(1)\">x</a>", "<a>x</a>"),
        ("<img src=\"vbscript:x\">", "<img>"),
        ("<img src=\"data:image/svg+xml,<svg>\">", "<img>"),
        ("<img srcset=\"a.png 1x, javascript:x 2x\">", "<img>"),
        ("<form action=\"javascript:x\">", "<form>"),
    ])
    func unsafeURLsRemoved(html: String, expected: String) {
        #expect(HTMLSanitizer.sanitize(html) == expected)
    }

    @Test("Raster data: images are allowed in src")
    func dataImageAllowed() {
        let html = "<img src=\"data:image/png;base64,AAAA\">"
        #expect(HTMLSanitizer.sanitize(html) == html)
    }

    @Test("Text between tags is untouched")
    func textBetweenTags() {
        #expect(HTMLSanitizer.sanitize("<div>\n1 < 2 and onclick=x\n</div>") == "<div>\n1 < 2 and onclick=x\n</div>")
    }
}

@Suite("URLPolicy")
struct URLPolicyTests {

    @Test("Safe link URLs", arguments: ["https://e.com", "http://e.com", "mailto:a@b.c", "file:///x", "#frag", "rel/path.md", "", "x-app://open"])
    func safeLinks(url: String) {
        #expect(URLPolicy.isSafe(url, context: .link))
    }

    @Test("Unsafe link URLs", arguments: ["javascript:x", "vbscript:x", "data:text/html,x", "data:image/png;base64,AA"])
    func unsafeLinks(url: String) {
        #expect(!URLPolicy.isSafe(url, context: .link))
    }

    @Test("Resolving relative URLs", arguments: [
        ("a.png", "file:///docs/a.png"),
        ("sub/a.png", "file:///docs/sub/a.png"),
        ("../a.png", "file:///a.png"),
        ("my file.md", "file:///docs/my%20file.md"),
        ("https://e.com/a", "https://e.com/a"),
        ("#top", "#top"),
        ("//cdn.example/x", "//cdn.example/x"),
        ("mailto:a@b.c", "mailto:a@b.c"),
    ])
    func resolve(url: String, expected: String) {
        let base = URL(fileURLWithPath: "/docs", isDirectory: true)
        #expect(URLPolicy.resolve(url, against: base) == expected)
    }

    @Test("A base URL without a trailing slash is still treated as a folder")
    func resolveAgainstFolderWithoutSlash() {
        let base = URL(string: "file:///docs")!
        #expect(URLPolicy.resolve("a.png", against: base) == "file:///docs/a.png")
    }

    @Test("Percent-encoding leaves valid URLs alone and encodes unsafe characters")
    func percentEncoding() {
        #expect(URLPolicy.percentEncodeUnsafe("https://e.com/a%20b?q=1#f") == "https://e.com/a%20b?q=1#f")
        #expect(URLPolicy.percentEncodeUnsafe("a b\"c") == "a%20b%22c")
    }
}

@Suite("Autolinker")
struct AutolinkerTests {

    @Test("Trailing punctuation rules", arguments: [
        ("www.e.com.", "www.e.com"),
        ("www.e.com/a?!", "www.e.com/a"),
        ("www.e.com/a)", "www.e.com/a"),
        ("www.e.com/(a)", "www.e.com/(a)"),
        ("www.e.com/a&amp;", "www.e.com/a"),
        ("www.e.com/a\"", "www.e.com/a"),
    ])
    func trailing(candidate: String, expected: String) {
        #expect(Autolinker.trimTrailing(candidate) == expected)
    }

    @Test("Output is escaped")
    func escapesText() {
        #expect(Autolinker.linkify("a < www.e.com") == "a &lt; <a href=\"http://www.e.com\">www.e.com</a>")
    }
}
