//
//  WindowKeyObserver.swift
//  viewMD
//
//  Reports when the window hosting a SwiftUI view becomes key, so menu
//  commands target the right window (see EditorModel.active).
//

import AppKit
import SwiftUI

/// An invisible view that calls `onBecomeKey` whenever its window becomes the
/// key window.
struct WindowKeyObserver: NSViewRepresentable {
    /// Called on the main thread when the hosting window becomes key.
    let onBecomeKey: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onBecomeKey = onBecomeKey
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onBecomeKey = onBecomeKey
    }

    /// The backing view; it re-subscribes whenever it moves to a window.
    final class ObserverView: NSView {
        var onBecomeKey: (() -> Void)?
        private var observer: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onBecomeKey?() }
            }
            if window.isKeyWindow { onBecomeKey?() }
        }

        isolated deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
