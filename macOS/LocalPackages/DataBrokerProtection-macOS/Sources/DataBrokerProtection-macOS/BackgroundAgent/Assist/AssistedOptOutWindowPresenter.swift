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
import Combine
import ConcurrencyExtensions
import DataBrokerProtectionCore
import DesignResourcesKit
import SwiftUI
import WebKit

@MainActor
final class AssistedOptOutWindowPresenter: AssistedOptOutPresenting {
    private var controllers: [AssistedOptOutID: AssistedOptOutWindowController] = [:]
    private let isApplicationActive: @MainActor () -> Bool
    private let requestUserAttention: @MainActor () -> Void
    private let makeWindow: @MainActor () -> NSWindow
    private let loadFavicon: @MainActor (AssistedOptOut.DataBroker) async -> Data?

    init(isApplicationActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
         requestUserAttention: @escaping @MainActor () -> Void = { NSApp.requestUserAttention(.criticalRequest) },
         makeWindow: @escaping @MainActor () -> NSWindow = AssistedOptOutWindowController.makeWindow,
         loadFavicon: @escaping @MainActor (AssistedOptOut.DataBroker) async -> Data? = AssistedOptOutBrokerLogo.faviconData) {
        self.isApplicationActive = isApplicationActive
        self.requestUserAttention = requestUserAttention
        self.makeWindow = makeWindow
        self.loadFavicon = loadFavicon
    }

    func present(_ session: AssistedOptOutSession) {
        show(controller(for: session), requestingAttention: false)
    }

    func userTurnStarted(in session: AssistedOptOutSession) {
        show(controller(for: session), requestingAttention: true)
    }

    func dismiss(_ session: AssistedOptOutSession) {
        controllers.removeValue(forKey: session.id)?.close()
    }

    private func show(_ controller: AssistedOptOutWindowController, requestingAttention: Bool) {
        guard let window = controller.window else { return }
        let applicationIsActive = isApplicationActive()
        if window.isMiniaturized, !requestingAttention || applicationIsActive {
            window.deminiaturize(nil)
        }
        if applicationIsActive {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
            if requestingAttention { requestUserAttention() }
        }
    }

    private func controller(for session: AssistedOptOutSession) -> AssistedOptOutWindowController {
        if let controller = controllers[session.id] { return controller }
        let controller = AssistedOptOutWindowController(session: session, window: makeWindow(), loadFavicon: loadFavicon) { [weak self] in
            self?.controllers[session.id] = nil
        }
        controllers[session.id] = controller
        return controller
    }
}

@MainActor
final class AssistedOptOutWindowController: NSWindowController, NSWindowDelegate {
    private let session: AssistedOptOutSession
    private let page = AssistedOptOutPageModel()
    private let onClose: @MainActor () -> Void
    private let frameView = AssistedOptOutGlowFrameView()
    private let coverView: NSView
    private var cancellables = Set<AnyCancellable>()
    private var isClosed = false

    init(session: AssistedOptOutSession, window: NSWindow,
         loadFavicon: @escaping @MainActor (AssistedOptOut.DataBroker) async -> Data?,
         onClose: @escaping @MainActor () -> Void) {
        self.session = session
        self.onClose = onClose
        coverView = AssistedOptOutHostingView(rootView: AssistedOptOutAppearanceRoot(content: AssistedOptOutPageCover(session: session)))
        window.title = AssistedOptOutText.removingFrom(session.broker.name)
        window.backgroundColor = NSColor(designSystemColor: .surfacePrimary, palette: .default)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 960, height: 600)
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView(loadFavicon: loadFavicon)
        observeSession()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.center()
        return window
    }

    private func makeContentView(loadFavicon: @escaping @MainActor (AssistedOptOut.DataBroker) async -> Data?) -> NSView {
        let content = AssistedOptOutBackgroundView()
        let browserArea = NSView()
        let topBar = AssistedOptOutHostingView(rootView: AssistedOptOutAppearanceRoot(content: AssistedOptOutTopBar(session: session, page: page)))
        let panel = AssistedOptOutHostingView(rootView: AssistedOptOutAppearanceRoot(content: AssistedOptOutStepsPanel(
            session: session,
            close: { [weak self] in self?.window?.performClose(nil) },
            loadFavicon: loadFavicon
        )))
        let divider = NSBox()
        divider.boxType = .separator

        for (view, superview) in [(topBar, browserArea), (frameView, browserArea), (coverView, frameView.contentView),
                                  (browserArea, content), (divider, content), (panel, content)] as [(NSView, NSView)] {
            view.translatesAutoresizingMaskIntoConstraints = false
            superview.addSubview(view)
        }
        NSLayoutConstraint.activate([
            browserArea.topAnchor.constraint(equalTo: content.topAnchor),
            browserArea.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            browserArea.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            topBar.topAnchor.constraint(equalTo: browserArea.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: browserArea.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: browserArea.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 46),
            frameView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            frameView.leadingAnchor.constraint(equalTo: browserArea.leadingAnchor, constant: 14),
            frameView.trailingAnchor.constraint(equalTo: browserArea.trailingAnchor, constant: -14),
            frameView.bottomAnchor.constraint(equalTo: browserArea.bottomAnchor, constant: -14),
            divider.leadingAnchor.constraint(equalTo: browserArea.trailingAnchor),
            divider.topAnchor.constraint(equalTo: content.topAnchor),
            divider.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            panel.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            panel.topAnchor.constraint(equalTo: content.topAnchor),
            panel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            panel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            panel.widthAnchor.constraint(equalToConstant: 380)
        ] + pinned(coverView, to: frameView.contentView))
        return content
    }

    private func pinned(_ view: NSView, to container: NSView) -> [NSLayoutConstraint] {
        [
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ]
    }

    private func observeSession() {
        session.$webView
            .compactMap { $0 }
            .sink { [weak self] webView in
                MainActor.assumeMainThread {
                    self?.embed(webView)
                }
            }
            .store(in: &cancellables)

        session.$phase
            .combineLatest(page.$hasLoadedPage)
            .sink { [weak self] phase, hasLoadedPage in
                MainActor.assumeMainThread {
                    self?.update(phase: phase, hasLoadedPage: hasLoadedPage)
                }
            }
            .store(in: &cancellables)
    }

    private func embed(_ webView: WKWebView) {
        guard webView.superview !== frameView.contentView else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        frameView.contentView.addSubview(webView, positioned: .below, relativeTo: coverView)
        NSLayoutConstraint.activate(pinned(webView, to: frameView.contentView))
        page.observe(webView)
    }

    private func update(phase: AssistedAttemptPhase, hasLoadedPage: Bool) {
        if !hasLoadedPage, phase == .userTurn || phase == .submitted {
            page.revealPage()
            return
        }
        coverView.isHidden = phase != .ready && hasLoadedPage
        switch phase {
        case .ready, .submitted: frameView.setGlow(.none)
        case .queued, .agentInControl: frameView.setGlow(.agent)
        case .userTurn: frameView.setGlow(.user)
        }
    }

    override func close() {
        guard !isClosed else { return }
        super.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Cancelling can synchronously dismiss and close this window before the delegate returns.
        session.requestCancel()
        return !isClosed
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosed else { return }
        isClosed = true
        cancellables.removeAll()
        page.stopObserving()
        session.isWindowKey = false
        session.requestCancel()
        onClose()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        session.isWindowKey = true
    }

    func windowDidResignKey(_ notification: Notification) {
        session.isWindowKey = false
    }
}
