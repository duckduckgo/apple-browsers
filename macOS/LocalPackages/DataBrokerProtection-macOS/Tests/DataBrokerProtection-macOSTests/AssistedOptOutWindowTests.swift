//
//  AssistedOptOutWindowTests.swift
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
import Testing
import WebKit
@testable import DataBrokerProtectionCore
@testable import DataBrokerProtection_macOS

@MainActor
@Suite(.serialized)
struct AssistedOptOutWindowTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [AssistedAttemptPhase.ready, .queued, .agentInControl, .userTurn, .submitted], [false, true])
    func unfinishedNativeCloseCancelsOnceIncludingSynchronousDismissal(phase: AssistedAttemptPhase, directClose: Bool) async throws {
        let session = makeSession()
        advance(session, to: phase)
        let window = makeOffscreenWindow()
        var confirmations = 0
        let presenter = AssistedOptOutWindowPresenter(isApplicationActive: { false }, requestUserAttention: {}, activateApplication: {},
                                                       makeWindow: { window }, loadFavicon: { _ in nil },
                                                       confirmStop: { _, _, completion in
            confirmations += 1
            completion(true)
        })
        var cancellations = 0
        session.onCancelRequested = { [weak presenter] session in
            cancellations += 1
            presenter?.dismiss(session)
        }
        presenter.present(session)
        weak var controller = window.windowController
        #expect(controller != nil)
        session.isWindowKey = true
        if directClose { window.close() } else { window.performClose(nil) }
        window.performClose(nil)
        try await Task.sleep(nanoseconds: 20_000_000)
        let isRunning = phase == .queued || phase == .agentInControl || phase == .userTurn
        #expect(confirmations == (isRunning && !directClose ? 1 : 0))
        #expect(cancellations == (phase == .submitted ? 0 : 1))
        #expect(!window.isVisible)
        #expect(!session.isWindowKey)
        #expect(controller == nil)
        if phase == .submitted {
            let lateWebView = WKWebView()
            session.attemptDidCreate(webView: lateWebView)
            #expect(lateWebView.superview == nil)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func decliningStopConfirmationKeepsAttemptAndWindow() {
        let session = makeSession()
        advance(session, to: .agentInControl)
        let window = makeOffscreenWindow()
        let presenter = AssistedOptOutWindowPresenter(isApplicationActive: { false }, requestUserAttention: {}, activateApplication: {},
                                                       makeWindow: { window }, loadFavicon: { _ in nil },
                                                       confirmStop: { _, _, completion in completion(false) })
        defer { presenter.dismiss(session) }
        var cancellations = 0
        session.onCancelRequested = { _ in cancellations += 1 }
        presenter.present(session)
        window.performClose(nil)
        #expect(cancellations == 0)
        #expect(window.isVisible)
        #expect(window.windowController != nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func repeatedStartReusesNativeWindowAndWebViewWithoutRestartingAttempt() async throws {
        let session = makeSession()
        let window = NonKeyAssistedWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        var windowCount = 0
        var beginCount = 0
        session.onBeginRequested = { _ in beginCount += 1 }
        let presenter = AssistedOptOutWindowPresenter(isApplicationActive: { false }, requestUserAttention: {}, activateApplication: {}, makeWindow: {
            windowCount += 1
            return window
        }, loadFavicon: { _ in nil })
        defer { presenter.dismiss(session) }
        presenter.present(session)
        #expect(session.phase == .ready)
        #expect(beginCount == 0)
        session.begin()
        session.begin()
        let webView = WKWebView()
        session.attemptDidCreate(webView: webView)
        let controller = try #require(window.windowController)
        let content = try #require(window.contentView)
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        #expect(descendants(of: content).contains { $0 === webView })
        #expect(descendants(of: content).compactMap { $0 as? NSTextField }.allSatisfy { !$0.isEditable })
        window.miniaturize(nil)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(window.isMiniaturized)
        #expect(!session.isCancelled)
        presenter.present(session)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(!window.isMiniaturized)
        #expect(window.windowController === controller)
        #expect(windowCount == 1)
        #expect(beginCount == 1)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)
        #expect(session.webView === webView)
        #expect(descendants(of: content).contains { $0 === webView })
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openingActivatesAgentButInactiveUserTurnOnlyRequestsAttention() {
        let session = makeSession()
        let window = makeOffscreenWindow()
        var active = false
        var attentionRequests = 0
        var activations = 0
        let presenter = AssistedOptOutWindowPresenter(isApplicationActive: { active }, requestUserAttention: { attentionRequests += 1 },
                                                       activateApplication: { activations += 1 },
                                                       makeWindow: { window }, loadFavicon: { _ in nil })
        defer { presenter.dismiss(session) }
        presenter.present(session)
        #expect(activations == 1)
        #expect(window.keyRequests == 1)
        presenter.userTurnStarted(in: session)
        #expect(activations == 1)
        #expect(attentionRequests == 1)
        #expect(window.keyRequests == 1)
        active = true
        presenter.userTurnStarted(in: session)
        #expect(window.keyRequests == 2)
        #expect(attentionRequests == 1)
        #expect(activations == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func pageTakesInputOnlyOutsideDuckDuckGosTurn() throws {
        let session = makeSession()
        let window = makeOffscreenWindow()
        let controller = AssistedOptOutWindowController(session: session, window: window, loadFavicon: { _ in nil }, onClose: {})
        defer { controller.close() }
        let webView = WKWebView()
        session.begin()
        session.attemptDidCreate(webView: webView)
        session.attemptWillRun(userAction)
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        let pagePoint = NSPoint(x: 100, y: 100)
        #expect(content.hitTest(pagePoint) is AssistedOptOutInputBlocker)
        #expect(window.firstResponder is AssistedOptOutInputBlocker)
        session.attemptNeedsUser(actionID: userAction.id)
        #expect(!(content.hitTest(pagePoint) is AssistedOptOutInputBlocker))
        #expect(window.firstResponder === webView)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func windowFloatsOnlyDuringUserTurn() {
        let session = makeSession()
        let window = makeOffscreenWindow()
        let controller = AssistedOptOutWindowController(session: session, window: window, loadFavicon: { _ in nil }, onClose: {})
        defer { controller.close() }
        session.begin()
        session.attemptDidCreate(webView: WKWebView())
        session.attemptWillRun(userAction)
        #expect(window.level == .normal)
        session.attemptNeedsUser(actionID: userAction.id)
        #expect(window.level == .floating)
        session.attemptWillRun(UserAssistAction(id: "next"))
        #expect(window.level == .normal)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [
        ("https://www.beenverified.com/svc/optout/search?q=1", "beenverified.com"),
        ("https://xn--bcher-kva.example/path", "bücher.example"),
        ("http://localhost:8080/form", "localhost:8080")
    ])
    func addressShowsDomainLikeBrowserAddressBar(url: String, expected: String) throws {
        #expect(AssistedOptOutAddress.addressBarHost(of: try #require(URL(string: url))) == expected)
    }

    private static let userStep = "Review your contact information and confirm this removal request before submitting"
    private var userAction: UserAssistAction {
        let json = Data("{\"step\":\"\(Self.userStep)\"}".utf8)
        return UserAssistAction(id: "review", json: json)
    }

    private func makeSession() -> AssistedOptOutSession {
        AssistedOptOutSession(id: .init(brokerId: 1, profileQueryId: 2, extractedProfileId: 3),
                              broker: .init(name: "Example Broker", url: "broker.example"),
                              steps: .init(titles: ["Open the opt-out form", Self.userStep, "Submit request"]))
    }

    private func advance(_ session: AssistedOptOutSession, to phase: AssistedAttemptPhase) {
        if phase != .ready { session.begin() }
        if phase == .agentInControl || phase == .userTurn { session.attemptWillRun(userAction) }
        if phase == .userTurn { session.attemptNeedsUser(actionID: userAction.id) }
        if phase == .submitted { session.markSubmitted() }
    }

    private func makeOffscreenWindow() -> NonActivatingAssistedWindow {
        NonActivatingAssistedWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1280, height: 820),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

@MainActor
private final class NonActivatingAssistedWindow: NSWindow {
    private(set) var keyRequests = 0

    override func makeKeyAndOrderFront(_ sender: Any?) {
        keyRequests += 1
        orderFront(sender)
    }
}

@MainActor
private final class NonKeyAssistedWindow: NSWindow {
    override var canBecomeKey: Bool { false }
}
