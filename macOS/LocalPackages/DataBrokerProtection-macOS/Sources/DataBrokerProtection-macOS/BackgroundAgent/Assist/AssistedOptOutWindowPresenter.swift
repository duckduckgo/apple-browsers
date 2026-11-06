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

/// Owns one window per assisted attempt, kept until the attempt ends so repeated starts bring the same window back.
@MainActor
final class AssistedOptOutWindowPresenter: AssistedOptOutPresenting {
    private var controllers: [AssistedOptOutID: AssistedOptOutWindowController] = [:]

    func present(_ session: AssistedOptOutSession) {
        let controller = controller(for: session)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.deminiaturize(nil)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func userTurnStarted(in session: AssistedOptOutSession) {
        let controller = controller(for: session)
        if NSApp.isActive {
            controller.showWindow(nil)
        } else {
            controller.window?.orderFront(nil)
            NSApp.requestUserAttention(.criticalRequest)
        }
    }

    func dismiss(_ session: AssistedOptOutSession) {
        controllers.removeValue(forKey: session.id)?.close()
    }

    private func controller(for session: AssistedOptOutSession) -> AssistedOptOutWindowController {
        if let controller = controllers[session.id] { return controller }
        let controller = AssistedOptOutWindowController(session: session) { [weak self] in
            self?.controllers[session.id] = nil
        }
        controllers[session.id] = controller
        return controller
    }
}

/// The attempt's page on the left under a bar showing its address and who is in control, and its steps on the right.
/// The window opens on an intro before the attempt starts, and the attempt's web view replaces it once it exists.
/// Closing the window while the attempt runs only hides it; closing it before the attempt starts cancels it.
@MainActor
final class AssistedOptOutWindowController: NSWindowController, NSWindowDelegate {
    private let session: AssistedOptOutSession
    private let page = AssistedOptOutPageModel()
    private let onClose: () -> Void
    private let frameView = AssistedOptOutGlowFrameView()
    private let coverView: NSView
    private var cancellables = Set<AnyCancellable>()
    private var isClosed = false

    init(session: AssistedOptOutSession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        coverView = AssistedOptOutHostingView(rootView: AssistedOptOutPageCover(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Removing you from \(session.broker.name)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 960, height: 600)
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
        window.center()
        observeSession()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeContentView() -> NSView {
        let content = NSView()
        let browserArea = NSView()
        let topBar = AssistedOptOutHostingView(rootView: AssistedOptOutTopBar(session: session, page: page))
        let panel = AssistedOptOutHostingView(rootView: AssistedOptOutStepsPanel(
            session: session,
            close: { [weak self] in self?.window?.performClose(nil) },
            stop: { [weak self] in self?.stop() }
        ))
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

    // Cancelling can make the queue dismiss this window before the call returns.
    private func stop() {
        session.requestCancel()
        if !isClosed { close() }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        switch session.phase {
        case .ready:
            session.requestCancel()
            return !isClosed
        case .submitted:
            return true
        case .queued, .agentInControl, .userTurn:
            session.isWindowKey = false
            sender.orderOut(nil)
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        page.stopObserving()
        session.isWindowKey = false
        onClose()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        session.isWindowKey = true
    }

    func windowDidResignKey(_ notification: Notification) {
        session.isWindowKey = false
    }
}
