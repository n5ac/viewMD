//
//  EditorSupportTests.swift
//  viewMDTests
//
//  Unit tests for the Phase 2 building blocks: minimal text diffs (REQ-013),
//  preview URLs and link routing (REQ-022), folder access matching, source
//  highlighting (REQ-023), the editor model (REQ-014) and render speed
//  (REQ-012).
//

import Foundation
import Testing
@testable import viewMD

@Suite("TextDiff")
struct TextDiffTests {

    @Test("Equal strings need no change")
    func equal() {
        #expect(TextDiff.replacement(from: "abc", to: "abc") == nil)
    }

    @Test("Minimal replacements", arguments: [
        ("hello world", "hello brave world", NSRange(location: 6, length: 0), "brave "),
        ("hello world", "hello", NSRange(location: 5, length: 6), ""),
        ("abc", "xbc", NSRange(location: 0, length: 1), "x"),
        ("", "new", NSRange(location: 0, length: 0), "new"),
        ("old", "", NSRange(location: 0, length: 3), ""),
        ("aa", "aaa", NSRange(location: 2, length: 0), "a"),
    ])
    func replacements(old: String, new: String, range: NSRange, text: String) {
        #expect(TextDiff.replacement(from: old, to: new) == TextReplacement(range: range, replacement: text))
    }

    @Test("Applying the replacement always yields the new string", arguments: [
        ("# Title\n\nPara", "# Title\n\nPara edited\n\n- item"),
        ("café 🎉 x", "café 🎊 x"),
        ("e\u{301}", "e\u{300}"),
        ("👍🏽 ok", "👍🏿 ok"),
        ("same start, different end", "same start, other end!"),
    ])
    func roundTrip(old: String, new: String) throws {
        let change = try #require(TextDiff.replacement(from: old, to: new))
        let result = (old as NSString).replacingCharacters(in: change.range, with: change.replacement)
        #expect(result == new)
    }

    @Test("Replacements never split a composed character")
    func composedCharacters() throws {
        let change = try #require(TextDiff.replacement(from: "a👍🏽b", to: "a👍🏿b"))
        // The whole emoji (thumbs up + skin tone) is replaced, not just the modifier.
        #expect(change.range == NSRange(location: 1, length: 4))
    }
}

@Suite("PreviewURLs and LinkRouter")
struct PreviewURLTests {

    @Test("Document base URL encodes the folder path")
    func documentBase() {
        let base = PreviewURLs.documentBaseURL(forFolder: URL(fileURLWithPath: "/Users/me/My Notes", isDirectory: true))
        #expect(base.absoluteString == "viewmd://doc/Users/me/My%20Notes/")
    }

    @Test("Renderer + base URL produce URLs the scheme handler maps back to files")
    func rendererRoundTrip() {
        let base = PreviewURLs.documentBaseURL(forFolder: URL(fileURLWithPath: "/Users/me/My Notes", isDirectory: true))
        let html = MarkdownRenderer(baseURL: base).render("![x](<img/a b.png>)").html
        #expect(html.contains("src=\"viewmd://doc/Users/me/My%20Notes/img/a%20b.png\""))
        let url = URL(string: "viewmd://doc/Users/me/My%20Notes/img/a%20b.png")!
        #expect(PreviewURLs.resource(for: url) == .file(URL(fileURLWithPath: "/Users/me/My Notes/img/a b.png")))
    }

    @Test("Bundled resources are served only from the allow-list")
    func bundled() {
        #expect(PreviewURLs.resource(for: URL(string: "viewmd://app/preview.html")!) == .bundled("preview.html"))
        #expect(PreviewURLs.resource(for: URL(string: "viewmd://app/bridge.js")!) == .bundled("bridge.js"))
        #expect(PreviewURLs.resource(for: URL(string: "viewmd://app/Info.plist")!) == .invalid)
        #expect(PreviewURLs.resource(for: URL(string: "viewmd://app/x/preview.html")!) == .invalid)
        #expect(PreviewURLs.resource(for: URL(string: "https://app/preview.html")!) == .invalid)
        #expect(PreviewURLs.resource(for: URL(string: "viewmd://other/x")!) == .invalid)
    }

    @Test("`..` in a document URL is normalized")
    func dotDot() {
        let url = URL(string: "viewmd://doc/Users/me/Notes/../a.png")!
        #expect(PreviewURLs.resource(for: url) == .file(URL(fileURLWithPath: "/Users/me/a.png")))
    }

    @Test("MIME types come from the extension")
    func mimeTypes() {
        #expect(PreviewURLs.mimeType(for: "a.png") == "image/png")
        #expect(PreviewURLs.mimeType(for: "preview.css") == "text/css")
        #expect(PreviewURLs.mimeType(for: "x.unknownext") == "application/octet-stream")
    }

    @Test("Link routing", arguments: [
        ("https://example.com", LinkDestination.external(URL(string: "https://example.com")!)),
        ("mailto:a@b.c", .external(URL(string: "mailto:a@b.c")!)),
        ("viewmd://doc/Users/me/other.md", .markdownDocument(URL(fileURLWithPath: "/Users/me/other.md"))),
        ("viewmd://doc/Users/me/other.MARKDOWN#part", .markdownDocument(URL(fileURLWithPath: "/Users/me/other.MARKDOWN"))),
        ("viewmd://doc/Users/me/file.pdf", .localFile(URL(fileURLWithPath: "/Users/me/file.pdf"))),
        ("viewmd://app/preview.html", .ignore),
        ("javascript:alert(1)", .ignore),
    ])
    func routing(href: String, expected: LinkDestination) {
        #expect(LinkRouter.destination(for: URL(string: href)!) == expected)
    }
}

@Suite("FolderAccessStore")
@MainActor
struct FolderAccessStoreTests {

    @Test("The deepest granted folder containing a file is chosen")
    func matching() {
        let folders = ["/Users/me", "/Users/me/Notes", "/Users/meg"]
        #expect(FolderAccessStore.grantedFolder(containing: "/Users/me/Notes/a.png", among: folders) == "/Users/me/Notes")
        #expect(FolderAccessStore.grantedFolder(containing: "/Users/me/b.png", among: folders) == "/Users/me")
        #expect(FolderAccessStore.grantedFolder(containing: "/Users/megan/c.png", among: folders) == nil)
        #expect(FolderAccessStore.grantedFolder(containing: "/Users/meg", among: folders) == nil)
    }

    @Test("Granting a folder persists a bookmark")
    func grantPersists() throws {
        let suite = "viewMDTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = FolderAccessStore(defaults: defaults)
        try store.grant(folder)
        #expect(store.grantedFolderPaths == [folder.standardizedFileURL.path])
        // A fresh store reads the same bookmark back.
        #expect(FolderAccessStore(defaults: defaults).grantedFolderPaths == [folder.standardizedFileURL.path])
    }
}

@Suite("MarkdownHighlighter")
struct MarkdownHighlighterTests {

    /// The styles applied to the first occurrence of `substring`.
    private func styles(in text: String, at substring: String) -> [MarkdownSyntaxStyle] {
        let target = (text as NSString).range(of: substring)
        return MarkdownHighlighter().runs(for: text)
            .filter { NSIntersectionRange($0.range, target).length > 0 }
            .map(\.style)
    }

    @Test("Recognizes the main constructs", arguments: [
        ("# Heading", "Heading", MarkdownSyntaxStyle.heading),
        ("a **bold** b", "bold", .strong),
        ("a *it* b", "it", .emphasis),
        ("a _it_ b", "it", .emphasis),
        ("a `code` b", "code", .code),
        ("see [link](https://x)", "link", .link),
        ("![alt](a.png)", "alt", .link),
        ("> quote", "quote", .quote),
        ("- item", "-", .listMarker),
        ("12. item", "12.", .listMarker),
        ("- [x] task", "[x]", .listMarker),
        ("---", "---", .rule),
    ])
    func constructs(text: String, substring: String, style: MarkdownSyntaxStyle) {
        #expect(styles(in: text, at: substring).contains(style))
    }

    @Test("Nothing inside a fenced code block is styled except as code")
    func fencedCodeIsOpaque() {
        let text = "```\n# not a heading\n**not bold**\n```\n# real"
        #expect(styles(in: text, at: "not a heading") == [.code])
        #expect(styles(in: text, at: "not bold") == [.code])
        #expect(styles(in: text, at: "real") == [.heading])
    }

    @Test("snake_case words aren't emphasis")
    func intrawordUnderscore() {
        #expect(!styles(in: "call my_func_name now", at: "func").contains(.emphasis))
    }
}

@Suite("EditorModel")
@MainActor
struct EditorModelTests {

    @Test("Toggling the source pane")
    func toggle() {
        let model = EditorModel()
        #expect(model.isSourceVisible)
        model.toggleSourcePane()
        #expect(!model.isSourceVisible)
        model.toggleSourcePane()
        #expect(model.isSourceVisible)
    }

    @Test("With the source hidden, commands target the preview")
    func activePane() {
        let model = EditorModel()
        model.lastFocusedPane = .source
        #expect(model.activePane == .source)
        model.isSourceVisible = false
        #expect(model.activePane == .preview)
    }
}

@Suite("Render performance")
struct RenderPerformanceTests {

    /// A realistic 5,000-line document mixing every construct.
    static let largeDocument: String = {
        let section = """
            ## Section heading

            A paragraph with **bold**, *italic*, `code`, a [link](https://example.com) and www.example.com.
            It continues on a second line.

            - item one
            - item two
              - nested
            - [x] task

            | a | b |
            |---|---|
            | 1 | 2 |

            ```swift
            let x = 1
            ```

            > quote

            """
        let lines = section.split(separator: "\n", omittingEmptySubsequences: false).count
        return String(repeating: section, count: 5_000 / (lines - 1) + 1)
    }()

    @Test("A 5,000-line document renders well within the 150 ms budget (REQ-012)")
    func largeDocumentRendersFast() {
        let document = Self.largeDocument
        #expect(document.split(separator: "\n", omittingEmptySubsequences: false).count >= 5_000)
        let renderer = MarkdownRenderer()
        _ = renderer.render(document) // warm up
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = renderer.render(document) }
        // The budget is 150 ms including the 30 ms debounce. Debug builds are
        // unoptimized, so this asserts with that margin removed.
        #expect(elapsed < .milliseconds(120), "Rendering took \(elapsed)")
    }

    @Test("Highlighting a 5,000-line document is fast enough for every keystroke")
    func largeDocumentHighlightsFast() {
        let document = Self.largeDocument
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = MarkdownHighlighter().runs(for: document) }
        #expect(elapsed < .milliseconds(100), "Highlighting took \(elapsed)")
    }
}
