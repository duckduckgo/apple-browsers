//
//  AssistedOptOutWindowPresenter.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import DataBrokerProtectionCore
import DesignResourcesKit
import SwiftUI
import WebKit

/// Owns one window per assisted attempt, kept until the attempt ends so repeated starts bring the same window back.
@MainActor
final class AssistedOptOutWindowPresenter: AssistedOptOutPresenting {
    private var controllers: [AssistedOptOutID: AssistedOptOutWindowController] = [:]

    func present(_ session: AssistedOptOutSession) {
        guard let controller = controller(for: session) else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.deminiaturize(nil)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func userTurnStarted(in session: AssistedOptOutSession) {
        guard let controller = controller(for: session) else { return }
        if NSApp.isActive {
            controller.showWindow(nil)
        } else {
            controller.window?.orderFront(nil)
            NSApp.requestUserAttention(.criticalRequest)
        }
    }

    func dismiss(_ session: AssistedOptOutSession) {
        controllers.removeValue(forKey: session.id)?.closeWithoutCancelling()
    }

    private func controller(for session: AssistedOptOutSession) -> AssistedOptOutWindowController? {
        if let controller = controllers[session.id] { return controller }
        guard let webView = session.webView else { return nil }
        let controller = AssistedOptOutWindowController(session: session, webView: webView) { [weak self] in
            self?.controllers[session.id] = nil
        }
        controllers[session.id] = controller
        return controller
    }
}

/// The attempt's web view on the left under a read-only address field, and its steps on the right.
/// Closing the window cancels the attempt; minimizing leaves it running.
@MainActor
final class AssistedOptOutWindowController: NSWindowController, NSWindowDelegate {
    private let session: AssistedOptOutSession
    private let onClose: () -> Void
    private var urlObservation: NSKeyValueObservation?
    private var isClosingWithoutCancelling = false

    init(session: AssistedOptOutSession, webView: WKWebView, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Removing you from \(session.broker.name)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 960, height: 600)
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView(webView: webView)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func closeWithoutCancelling() {
        isClosingWithoutCancelling = true
        close()
    }

    private func makeContentView(webView: WKWebView) -> NSView {
        let content = NSView()
        let addressField = NSTextField(labelWithString: "")
        addressField.isSelectable = true
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.textColor = .secondaryLabelColor
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak addressField] webView, _ in
            let url = webView.url
            MainActor.assumeIsolated {
                addressField?.stringValue = ["http", "https"].contains(url?.scheme) ? url?.absoluteString ?? "" : ""
            }
        }

        let panel = NSHostingView(rootView: AssistedOptOutStepsPanel(session: session) { [weak self] in self?.window?.performClose(nil) })
        if #available(macOS 13.0, *) {
            panel.sizingOptions = []
        }
        let divider = NSBox()
        divider.boxType = .separator

        webView.removeFromSuperview()
        for view in [addressField, webView, divider, panel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            addressField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            addressField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            addressField.trailingAnchor.constraint(equalTo: webView.trailingAnchor, constant: -16),
            webView.topAnchor.constraint(equalTo: addressField.bottomAnchor, constant: 12),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: webView.trailingAnchor),
            divider.topAnchor.constraint(equalTo: content.topAnchor),
            divider.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            panel.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            panel.topAnchor.constraint(equalTo: content.topAnchor),
            panel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            panel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            panel.widthAnchor.constraint(equalToConstant: 380)
        ])
        return content
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        urlObservation?.invalidate()
        session.isWindowKey = false
        if !isClosingWithoutCancelling {
            session.requestCancel()
        }
        onClose()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        session.isWindowKey = true
    }

    func windowDidResignKey(_ notification: Notification) {
        session.isWindowKey = false
    }
}
