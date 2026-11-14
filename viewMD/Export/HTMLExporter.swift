//
//  HTMLExporter.swift
//  viewMD
//
//  Builds standalone HTML documents for File ▸ Export (REQ-017) and as the
//  source for PDF export (REQ-018).
//

import Foundation

/// Produces a complete, self-contained HTML document from Markdown.
///
/// The output has the preview's stylesheet and the highlight.js themes
/// inlined (both follow light/dark mode, REQ-021), code blocks highlighted
/// ahead of time, and no scripts. The preview's editing attributes
/// (`data-src`, `data-md-*`) are removed. Relative links and images keep
/// the paths written in the Markdown, so the file works when saved next to
/// the document.
@MainActor
struct HTMLExporter {

    /// Highlights code blocks; shared because loading highlight.js is costly.
    private static let highlighter = CodeHighlighter()

    /// The bundle holding `preview.css` and the highlight themes.
    var bundle: Bundle = .main

    /// Builds the HTML document.
    ///
    /// - Parameters:
    ///   - markdown: The Markdown source.
    ///   - title: The document title (usually the file name without its
    ///     extension).
    ///   - baseURL: The URL relative links resolve against. `nil` (the
    ///     default) keeps them as written. PDF export passes the preview's
    ///     document base so local images load.
    /// - Returns: The HTML document.
    func makeHTML(markdown: String, title: String, baseURL: URL? = nil) -> String {
        let rendered = MarkdownRenderer(baseURL: baseURL).render(markdown).html
        let body = Self.stripEditingAttributes(Self.highlighter.highlight(rendered))
        return """
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <meta name="generator" content="viewMD">
            <title>\(HTMLEscaping.escape(title))</title>
            <style>
            \(stylesheet())
            </style>
            </head>
            <body>
            <article class="markdown-body">
            \(body)</article>
            </body>
            </html>

            """
    }

    /// The inlined CSS: the preview stylesheet plus the light and dark
    /// highlight themes, each limited to its color scheme.
    func stylesheet() -> String {
        let preview = resource("preview", "css")
        let light = resource("highlight-github", "css")
        let dark = resource("highlight-github-dark", "css")
        return """
            \(preview)
            @media (prefers-color-scheme: light) { \(light) }
            @media (prefers-color-scheme: dark) { \(dark) }
            @media print { \(light) }
            """
    }

    /// Reads a bundled text resource, or `""` if it's missing.
    private func resource(_ name: String, _ ext: String) -> String {
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Removes the attributes the preview uses for editing, which mean
    /// nothing in an exported file.
    ///
    /// - Parameter html: Rendered HTML.
    /// - Returns: The HTML without `data-src` and `data-md-*` attributes.
    nonisolated static func stripEditingAttributes(_ html: String) -> String {
        html.replacingOccurrences(of: #" data-(?:src|md-href|md-src)="[^"]*""#, with: "", options: .regularExpression)
    }
}
