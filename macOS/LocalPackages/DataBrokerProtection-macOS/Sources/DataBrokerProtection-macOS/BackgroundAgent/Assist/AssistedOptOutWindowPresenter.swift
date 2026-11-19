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

typealias AssistedOptOutStopConfirmation = @MainActor (NSWindow, AssistedOptOut.DataBroker, @escaping @MainActor (Bool) -> Void) -> Void

/// Opens one window per assisted opt-out attempt. Runs in the background agent when the user starts an attempt from the dashboard.
@MainActor
final class AssistedOptOutWindowPresenter: AssistedOptOutPresenting {
    private var controllers: [AssistedOptOutID: AssistedOptOutWindowController] = [:]
    private let isApplicationActive: @MainActor () -> Bool
    private let requestUserAttention: @MainActor () -> Void
    private let activateApplication: @MainActor () -> Void
    private let makeWindow: @MainActor () -> NSWindow
    private let loadFavicon: @MainActor (AssistedOptOut.DataBroker) async -> Data?
    private let confirmStop: AssistedOptOutStopConfirmation

    init(isApplicationActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
         requestUserAttention: @escaping @MainActor () -> Void = { NSApp.requestUserAttention(.criticalRequest) },
         activateApplication: @escaping @MainActor () -> Void = AssistedOptOutWindowPresenter.activateAgent,
         makeWindow: @escaping @MainActor () -> NSWindow = AssistedOptOutWindowController.makeWindow,
         loadFavicon: @escaping @MainActor (AssistedOptOut.DataBroker) async -> Data? = AssistedOptOutBrokerLogo.faviconData,
         confirmStop: @escaping AssistedOptOutStopConfirmation = AssistedOptOutWindowController.presentStopConfirmation) {
        self.isApplicationActive = isApplicationActive
        self.requestUserAttention = requestUserAttention
        self.activateApplication = activateApplication
        self.makeWindow = makeWindow
        self.loadFavicon = loadFavicon
        self.confirmStop = confirmStop
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
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        // When the user's turn arrives while they're in another app, bounce the Dock icon instead of taking focus from what they're typing.
        if requestingAttention, !applicationIsActive {
            window.orderFrontRegardless()
            requestUserAttention()
        } else {
            if !applicationIsActive { activateApplication() }
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func activateAgent() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func controller(for session: AssistedOptOutSession) -> AssistedOptOutWindowController {
        if let controller = controllers[session.id] { return controller }
        let controller = AssistedOptOutWindowController(session: session, window: makeWindow(), loadFavicon: loadFavicon,
                                                        confirmStop: confirmStop) { [weak self] in
            self?.controllers[session.id] = nil
        }
        controllers[session.id] = controller
        return controller
    }
}

/// The window for one attempt, with the broker page beside the steps panel. While DuckDuckGo is in control it blocks input to the page.
@MainActor
final class AssistedOptOutWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let addressItem = NSToolbarItem.Identifier("AssistedOptOutAddress")
    private static let statusItem = NSToolbarItem.Identifier("AssistedOptOutStatus")

    private let session: AssistedOptOutSession
    private let page = AssistedOptOutPageModel()
    private let confirmStop: AssistedOptOutStopConfirmation
    private let onClose: @MainActor () -> Void
    private let pageView = NSView()
    private let edgeView = AssistedOptOutEdgeOverlayView()
    private let coverView: NSView
    private var cancellables = Set<AnyCancellable>()
    private var isClosed = false
    private var isConfirmingStop = false
    private weak var statusToolbarItem: NSToolbarItem?

    init(session: AssistedOptOutSession, window: NSWindow,
         loadFavicon: @escaping @MainActor (AssistedOptOut.DataBroker) async -> Data?,
         confirmStop: @escaping AssistedOptOutStopConfirmation = AssistedOptOutWindowController.presentStopConfirmation,
         onClose: @escaping @MainActor () -> Void) {
        self.session = session
        self.confirmStop = confirmStop
        self.onClose = onClose
        coverView = AssistedOptOutHostingView(rootView: AssistedOptOutAppearanceRoot(content: AssistedOptOutPageCover(session: session)))
        window.title = AssistedOptOutText.removingFrom(session.broker.name)
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.backgroundColor = NSColor(designSystemColor: .surfacePrimary, palette: .default)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 560)
        super.init(window: window)
        window.delegate = self
        let toolbar = NSToolbar(identifier: "AssistedOptOutToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.contentView = makeContentView(loadFavicon: loadFavicon)
        observeSession()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.center()
        return window
    }

    static func presentStopConfirmation(in window: NSWindow, broker: AssistedOptOut.DataBroker, completion: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = AssistedOptOutText.stopConfirmationTitle(broker.name)
        alert.informativeText = AssistedOptOutText.stopConfirmationDetail
        alert.addButton(withTitle: AssistedOptOutText.keepGoing)
        alert.addButton(withTitle: AssistedOptOutText.stop).hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeMainThread {
                completion(response == .alertSecondButtonReturn)
            }
        }
    }

    private func makeContentView(loadFavicon: @escaping @MainActor (AssistedOptOut.DataBroker) async -> Data?) -> NSView {
        let content = AssistedOptOutBackgroundView()
        let panel = AssistedOptOutHostingView(rootView: AssistedOptOutAppearanceRoot(content: AssistedOptOutStepsPanel(
            session: session,
            close: { [weak self] in self?.window?.performClose(nil) },
            loadFavicon: loadFavicon
        )))
        // A separator's orientation comes from its initial frame. A zero frame makes it horizontal, and its height then collapses the window.
        let divider = NSBox(frame: NSRect(x: 0, y: 0, width: 1, height: 100))
        divider.boxType = .separator

        for (view, superview) in [(coverView, pageView), (pageView, content), (edgeView, content),
                                  (divider, content), (panel, content)] as [(NSView, NSView)] {
            view.translatesAutoresizingMaskIntoConstraints = false
            superview.addSubview(view)
        }
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: content.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pageView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: pageView.trailingAnchor),
            divider.topAnchor.constraint(equalTo: content.topAnchor),
            divider.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            panel.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            panel.topAnchor.constraint(equalTo: content.topAnchor),
            panel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            panel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            panel.widthAnchor.constraint(equalToConstant: 320)
        ] + pinned(coverView, to: pageView) + pinned(edgeView, to: pageView))
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
        guard webView.superview !== pageView else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        pageView.addSubview(webView, positioned: .below, relativeTo: coverView)
        NSLayoutConstraint.activate(pinned(webView, to: pageView))
        (webView as? UserInputIgnoring)?.ignoresUserInput = ignoresPageInput(in: session.phase)
        page.observe(webView)
    }

    private func update(phase: AssistedAttemptPhase, hasLoadedPage: Bool) {
        // Keep the window above other apps while the user has a step to do, so the broker page can't get buried.
        window?.level = phase == .userTurn ? .floating : .normal
        let showsPage = hasLoadedPage || phase == .userTurn || phase == .submitted
        if showsPage, !hasLoadedPage { page.revealPage() }
        coverView.isHidden = phase != .ready && showsPage
        styleStatusItem(for: phase)
        switch phase {
        case .ready, .submitted, .queued, .agentInControl:
            edgeView.setEdge(.none)
        case .userTurn:
            edgeView.setEdge(.user)
            if let webView = session.webView { window?.makeFirstResponder(webView) }
        }
        (session.webView as? UserInputIgnoring)?.ignoresUserInput = ignoresPageInput(in: phase)
    }

    /// The user can watch but not type or click into the page while DuckDuckGo fills it in.
    private func ignoresPageInput(in phase: AssistedAttemptPhase) -> Bool {
        phase == .queued || phase == .agentInControl
    }

    private func styleStatusItem(for phase: AssistedAttemptPhase) {
        guard #available(macOS 26.0, *), let statusToolbarItem else { return }
        let isAgentInControl = phase == .queued || phase == .agentInControl
        statusToolbarItem.style = isAgentInControl ? .prominent : .plain
        statusToolbarItem.backgroundTintColor = isAgentInControl ? .black : nil
    }

    override func close() {
        guard !isClosed else { return }
        super.close()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.addressItem, .flexibleSpace, Self.statusItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let view: NSView
        switch itemIdentifier {
        case Self.addressItem:
            view = NSHostingView(rootView: AssistedOptOutAppearanceRoot(content: AssistedOptOutAddress(session: session, page: page)))
        case Self.statusItem:
            view = NSHostingView(rootView: AssistedOptOutAppearanceRoot(content: AssistedOptOutStatus(session: session)))
        default:
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = view
        if itemIdentifier == Self.statusItem {
            statusToolbarItem = item
            styleStatusItem(for: session.phase)
        }
        return item
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isClosed else { return false }
        switch session.phase {
        case .submitted:
            return true
        case .ready:
            // Nothing has started yet, so cancel without asking.
            session.requestCancel()
            return false
        case .queued, .agentInControl, .userTurn:
            break
        }
        guard !isConfirmingStop else { return false }
        isConfirmingStop = true
        confirmStop(sender, session.broker) { [weak self] confirmed in
            self?.isConfirmingStop = false
            if confirmed { self?.session.requestCancel() }
        }
        return false
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
