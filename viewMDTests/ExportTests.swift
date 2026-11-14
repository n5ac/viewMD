//
//  ExportTests.swift
//  viewMDTests
//
//  Unit tests for HTML export (REQ-017), PDF export (REQ-018), exported
//  appearance (REQ-021) and pre-highlighted code (REQ-019).
//

import Foundation
import PDFKit
import Testing
@testable import viewMD

@Suite("HTML export")
@MainActor
struct HTMLExportTests {

    let sample = """
        # Report <draft>

        Some **bold** text and ![chart](images/chart.png).

        ```swift
        let answer = 42
        ```
        """

    @Test("Produces a complete, standalone document")
    func standaloneDocument() {
        let html = HTMLExporter().makeHTML(markdown: sample, title: "Report <draft>")
        #expect(html.hasPrefix("<!doctype html>"))
        #expect(html.contains("<title>Report &lt;draft&gt;</title>"))
        #expect(html.contains("<style>"))
        #expect(html.contains(".markdown-body"), "Preview stylesheet should be inlined")
        #expect(html.contains("<article class=\"markdown-body\">"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(!html.contains("<link "), "No external stylesheets")
    }

    @Test("Contains no scripts and no editing attributes")
    func noScriptsOrEditingAttributes() {
        let html = HTMLExporter().makeHTML(markdown: sample + "\n\n<script>x()</script>", title: "T")
        #expect(!html.contains("<script"))
        #expect(!html.contains("data-src="))
        #expect(!html.contains("data-md-"))
    }

    @Test("Relative image paths stay as written")
    func relativePathsKept() {
        let html = HTMLExporter().makeHTML(markdown: sample, title: "T")
        #expect(html.contains("src=\"images/chart.png\""))
    }

    @Test("Code blocks are highlighted ahead of time (REQ-019)")
    func codeHighlighted() {
        let html = HTMLExporter().makeHTML(markdown: sample, title: "T")
        #expect(html.contains("<code class=\"hljs language-swift\">"))
        #expect(html.contains("hljs-keyword"))
        #expect(html.contains("hljs-number"))
    }

    @Test("Styles cover light, dark and print (REQ-021)")
    func colorSchemes() {
        let css = HTMLExporter().stylesheet()
        #expect(css.contains("@media (prefers-color-scheme: dark)"))
        #expect(css.contains("@media (prefers-color-scheme: light)"))
        #expect(css.contains("@media print"))
    }

    @Test("Editing attributes are stripped")
    func stripAttributes() {
        let html = "<p data-src=\"1-2\">a <a href=\"viewmd://doc/x\" data-md-href=\"x\">b</a><img src=\"s\" data-md-src=\"t\" /></p>"
        #expect(HTMLExporter.stripEditingAttributes(html) == "<p>a <a href=\"viewmd://doc/x\">b</a><img src=\"s\" /></p>")
    }
}

@Suite("CodeHighlighter")
@MainActor
struct CodeHighlighterTests {

    @Test("highlight.js loads from the bundle")
    func loads() {
        #expect(CodeHighlighter().isAvailable)
    }

    @Test("Unknown languages and plain blocks are left alone")
    func unknownLanguage() {
        let html = "<pre><code class=\"language-notareallanguage\">x &lt; y</code></pre><pre><code>plain</code></pre>"
        #expect(CodeHighlighter().highlight(html) == html)
    }

    @Test("Escaped code is unescaped before highlighting and re-escaped by highlight.js")
    func escaping() {
        let html = "<pre><code class=\"language-swift\">if a &lt; b &amp;&amp; c { }</code></pre>"
        let output = CodeHighlighter().highlight(html)
        #expect(output.contains("&lt;"))
        #expect(output.contains("&amp;&amp;"))
        #expect(!output.contains("&amp;lt;"), "Must not double-escape")
    }

    @Test("Unescape reverses HTMLEscaping")
    func unescapeRoundTrip() {
        let text = "a < b && \"c\" > d"
        #expect(CodeHighlighter.unescape(HTMLEscaping.escape(text)) == text)
    }
}

@Suite("PDF export")
@MainActor
struct PDFExportTests {

    @Test("Long documents paginate, and the text is in the PDF")
    func paginatedPDF() async throws {
        let section = "## Section\n\n" + String(repeating: "A line of body text that fills the page. ", count: 40) + "\n\n"
        let markdown = "# PDF Export Test\n\n" + String(repeating: section, count: 12)
        let html = HTMLExporter().makeHTML(markdown: markdown, title: "PDF Export Test")
        let data = try await PDFExporter().makePDF(html: html)
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount >= 2, "Expected several pages, got \(pdf.pageCount)")
        #expect(pdf.string?.contains("PDF Export Test") == true)
        #expect(pdf.string?.contains("A line of body text") == true)
    }

    @Test("Export file names follow the document name")
    func fileNames() {
        let url = URL(fileURLWithPath: "/tmp/Notes.md")
        #expect(ExportController.suggestedFileName(for: url, format: .pdf) == "Notes.pdf")
        #expect(ExportController.suggestedFileName(for: url, format: .html) == "Notes.html")
        #expect(ExportController.suggestedFileName(for: nil, format: .pdf) == "Untitled.pdf")
    }

    @Test("HTML export data is the UTF-8 page")
    func htmlData() async throws {
        let data = try await ExportController.makeData(.html, markdown: "# Hi ✓", title: "Hi", fileURL: nil)
        let html = try #require(String(data: data, encoding: .utf8))
        #expect(html.contains("Hi ✓"))
    }
}
