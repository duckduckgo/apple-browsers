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
import XCTest
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
        let presenter = AssistedOptOutWindowPresenter(isApplicationActive: { false }, requestUserAttention: {},
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
        let presenter = AssistedOptOutWindowPresenter(isApplicationActive: { false }, requestUserAttention: {},
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
        let presenter = AssistedOptOutWindowPresenter(isApplicationActive: { false }, requestUserAttention: {}, makeWindow: {
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
    func inactiveUserTurnRequestsAttentionWithoutRequestingKeyWindow() {
        let session = makeSession()
        let window = makeOffscreenWindow()
        var active = false
        var attentionRequests = 0
        let presenter = AssistedOptOutWindowPresenter(isApplicationActive: { active }, requestUserAttention: { attentionRequests += 1 },
                                                       makeWindow: { window }, loadFavicon: { _ in nil })
        defer { presenter.dismiss(session) }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        presenter.present(session)
        presenter.userTurnStarted(in: session)
        #expect(attentionRequests == 1)
        #expect(window.keyRequests == 0)
        #expect(!window.isKeyWindow)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)
        active = true
        presenter.userTurnStarted(in: session)
        #expect(window.keyRequests == 1)
        #expect(attentionRequests == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func realHiddenWindowRendersPhasesAndLiveAppearanceWithLocalPage() async throws {
        let session = makeSession()
        let window = makeOffscreenWindow()
        let controller = AssistedOptOutWindowController(session: session, window: window, loadFavicon: { _ in nil }, onClose: {})
        defer { controller.close() }
        let directory = URL(fileURLWithPath: "/tmp/pir-user-assist-stack/pr4-proof", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await captureBothAppearances(window, phase: "ready", directory: directory)
        session.begin()
        let webView = try await loadFixture(in: session)
        let pageTitle: String? = try await webView.evaluateJavaScript("document.querySelector('h1').textContent")
        #expect(pageTitle == "Removal request")
        session.attemptWillRun(userAction)
        session.attemptNeedsUser(actionID: userAction.id)
        #expect(session.currentStepTitle == Self.userStep)
        try await captureBothAppearances(window, phase: "user-turn", directory: directory)
        window.setFrame(NSRect(origin: window.frame.origin, size: window.minSize), display: false)
        try await capture(window, name: "user-turn-minimum-dark", appearance: .darkAqua, directory: directory)
        window.setContentSize(NSSize(width: 1280, height: 820))
        session.markSubmitted()
        try await captureBothAppearances(window, phase: "submitted", directory: directory)
        #expect(!window.isVisible)
        let fallbackSession = makeSession(titles: [])
        let fallbackWindow = makeOffscreenWindow()
        let fallbackController = AssistedOptOutWindowController(session: fallbackSession, window: fallbackWindow, loadFavicon: { _ in nil }, onClose: {})
        defer { fallbackController.close() }
        fallbackSession.begin()
        _ = try await loadFixture(in: fallbackSession)
        fallbackSession.attemptNeedsUser(actionID: "unlabeled")
        try await capture(fallbackWindow, name: "user-turn-no-step-dark", appearance: .darkAqua, directory: directory)
        #expect(fallbackSession.currentStepTitle == nil)
        #expect(!fallbackWindow.isVisible)
    }

    private static let userStep = "Review your contact information and confirm this removal request before submitting"
    private static let fixtureHTML = """
    <!doctype html><html><head><meta name="color-scheme" content="light dark"><style>
    body { font: 17px system-ui; padding: 40px; } main { max-width: 540px; }
    label { display: block; margin: 24px 0; } input { display: block; padding: 10px; width: 90%; }
    section { border: 3px solid #d7a62b; border-radius: 8px; padding: 20px; margin-top: 24px; }
    button { font: inherit; padding: 10px 20px; } p { line-height: 1.5; }
    </style></head><body><main><h1>Removal request</h1><p>This local fixture represents the broker form.</p>
    <label>Name<input value="Example Person" readonly></label>
    <label>Email<input value="person@example.com" readonly></label>
    <section><h2>Review and confirm</h2><p>Check your contact information, then submit this removal request.</p>
    <button>Submit request</button></section></main></body></html>
    """

    private var userAction: UserAssistAction {
        let json = Data("{\"step\":\"\(Self.userStep)\"}".utf8)
        return UserAssistAction(id: "review", json: json)
    }

    private func makeSession(titles: [String]? = nil) -> AssistedOptOutSession {
        AssistedOptOutSession(id: .init(brokerId: 1, profileQueryId: 2, extractedProfileId: 3),
                              broker: .init(name: "Example Broker", url: "broker.example"), recordCount: 1,
                              steps: .init(titles: titles ?? ["Open the opt-out form", Self.userStep, "Submit request"]))
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

    private func loadFixture(in session: AssistedOptOutSession) async throws -> WKWebView {
        let webView = WKWebView()
        let navigation = FixtureNavigation()
        webView.navigationDelegate = navigation
        session.attemptDidCreate(webView: webView)
        webView.loadHTMLString(Self.fixtureHTML, baseURL: URL(string: "https://broker.example/opt-out"))
        let result = await XCTWaiter.fulfillment(of: [navigation.finished], timeout: 10)
        #expect(result == .completed)
        return webView
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func captureBothAppearances(_ window: NSWindow, phase: String, directory: URL) async throws {
        let light = try await capture(window, name: "\(phase)-light", appearance: .aqua, directory: directory)
        let dark = try await capture(window, name: "\(phase)-dark", appearance: .darkAqua, directory: directory)
        #expect(light != dark)
    }

    @discardableResult
    private func capture(_ window: NSWindow, name: String, appearance: NSAppearance.Name, directory: URL) async throws -> Data {
        window.appearance = NSAppearance(named: appearance)
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        content.displayIfNeeded()
        let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(bitmap.pixelsWide >= Int(content.bounds.width))
        #expect(bitmap.pixelsHigh >= Int(content.bounds.height))
        #expect(data.count > 5000)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
        return data
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

@MainActor
private final class FixtureNavigation: NSObject, WKNavigationDelegate {
    let finished = XCTestExpectation(description: "Local HTML navigation finished")

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }
}
