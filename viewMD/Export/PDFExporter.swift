//
//  PDFExporter.swift
//  viewMD
//
//  Turns exported HTML into a paginated PDF (REQ-018).
//
//  Copyright (C) 2026 Stephen Hicks, N5AC
//
//  This file is part of viewMD.
//
//  viewMD is free software: you can redistribute it and/or modify it under
//  the terms of the GNU General Public License as published by the Free
//  Software Foundation, either version 3 of the License, or (at your option)
//  any later version.
//
//  viewMD is distributed in the hope that it will be useful, but WITHOUT ANY
//  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
//  FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
//  details.
//
//  You should have received a copy of the GNU General Public License along
//  with viewMD. If not, see <https://www.gnu.org/licenses/>.
//

import AppKit
import WebKit

/// Errors from PDF export.
enum PDFExportError: LocalizedError {
    /// The HTML didn't finish loading in the off-screen web view.
    case loadFailed(any Error)
    /// The print system didn't produce a file.
    case noOutput

    var errorDescription: String? {
        switch self {
        case .loadFailed(let error): return "The document couldn't be laid out for PDF: \(error.localizedDescription)"
        case .noOutput: return "The PDF couldn't be created."
        }
    }
}

/// Lays out HTML in an off-screen `WKWebView` and prints it to PDF.
///
/// Printing, unlike `WKWebView.createPDF`, paginates the content. The
/// stylesheet's `@media print` rules then apply: light colors, no page
/// breaks inside code blocks, tables or images, and headings kept with the
/// text that follows.
@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {

    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, any Error>?
    private let schemeHandler = PreviewSchemeHandler(folderAccess: .shared)

    /// Renders `html` to a PDF document.
    ///
    /// - Parameters:
    ///   - html: A complete HTML document (from ``HTMLExporter``). Local
    ///     images should use `viewmd://doc/` URLs so the app can load them.
    ///   - printInfo: Paper size and margins. Defaults to the user's default
    ///     paper with 0.6-inch margins.
    /// - Returns: The PDF data.
    /// - Throws: ``PDFExportError`` if layout or printing fails.
    func makePDF(html: String, printInfo: NSPrintInfo = PDFExporter.defaultPrintInfo()) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: PreviewURLs.scheme)
        // Scripts aren't needed: exported HTML has none.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 800), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        defer { self.webView = nil }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "viewmd://app/"))
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("viewMD-export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let info = printInfo.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = outputURL
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // WKWebView's print operation needs a real view size to lay out pages.
        operation.view?.frame = webView.bounds
        let host = Self.hostWindow(for: webView)
        defer {
            host.orderOut(nil)
            host.contentView = nil
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let helper = PrintCompletion(continuation)
            operation.runModal(for: host, delegate: helper,
                               didRun: #selector(PrintCompletion.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }

        guard let data = try? Data(contentsOf: outputURL), !data.isEmpty else { throw PDFExportError.noOutput }
        return data
    }

    /// The user's default paper size with comfortable margins.
    nonisolated static func defaultPrintInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        let margin: CGFloat = 0.6 * 72
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        return info
    }

    /// An invisible window to host the print operation. WebKit needs the web
    /// view in a window to print, but the user shouldn't see it.
    private static func hostWindow(for webView: WKWebView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: webView.frame.width, height: webView.frame.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.alphaValue = 0
        window.orderBack(nil)
        return window
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        loadContinuation?.resume(throwing: PDFExportError.loadFailed(error))
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        loadContinuation?.resume(throwing: PDFExportError.loadFailed(error))
        loadContinuation = nil
    }
}

/// Bridges `NSPrintOperation`'s delegate callback to a continuation.
private final class PrintCompletion: NSObject {
    private var continuation: CheckedContinuation<Void, Never>?
    /// Keeps the helper alive until the print operation calls back.
    private var retainSelf: PrintCompletion?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
        super.init()
        retainSelf = self
    }

    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        continuation?.resume()
        continuation = nil
        retainSelf = nil
    }
}
