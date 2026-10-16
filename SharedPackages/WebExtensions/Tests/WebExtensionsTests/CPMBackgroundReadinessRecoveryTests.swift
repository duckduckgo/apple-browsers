//
//  CPMBackgroundReadinessRecoveryTests.swift
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

import XCTest
import WebKit
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundReadinessRecoveryTests: XCTestCase {
    private let url = URL(string: "https://example.com/page?q=one")!
    private var enabled = true
    private var backgrounded = false
    private var date = Date()
    private var reloads = 0
    private let reloadNavigation = WKNavigation()
    private var outcomes: [CPMRecoveryOutcome] = []

    private func makeRecovery() -> CPMBackgroundReadinessRecovery {
        CPMBackgroundReadinessRecovery(isEnabled: { [unowned self] in enabled },
                                       isApplicationInBackground: { [unowned self] in backgrounded },
                                       instrumentation: Instrumentation { [unowned self] in outcomes.append($0) },
                                       now: { [unowned self] in date })
    }

    private func pendingDocument(_ recovery: CPMBackgroundReadinessRecovery) -> UUID {
        let id = UUID()
        recovery.backgroundStarted(id)
        recovery.navigationStarted(in: "tab")
        recovery.navigationCommitted(in: "tab", url: url)
        recovery.registerDocument(in: "tab") { [unowned self] in
            { [unowned self] in reloads += 1; return reloadNavigation }
        }
        return id
    }

    private func drain() async { for _ in 0..<10 { await Task.yield() } }

    func testRequiresFailureAndSuccessfulBackgroundThenReloadsOnlyOnce() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.initializationFailed(in: "tab")
        await drain()
        XCTAssertEqual(reloads, 0)
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(outcomes, [.reloadStarted])
        recovery.navigationStarted(in: "tab")
        recovery.matchNavigationStarted(in: "tab") { [reloadNavigation] in $0 === reloadNavigation }
        recovery.navigationCommitted(in: "tab", url: url)
        recovery.responseReceived(in: "tab")
        recovery.responseReceived(in: "tab")
        XCTAssertEqual(outcomes, [.reloadStarted, .responseReceived])
    }

    func testHealthyLateResponseAvoidsReload() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.responseReceived(in: "tab")
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertEqual(reloads, 0)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testChangedClosedFailedAndReplacedDocumentsAreNotReloaded() async {
        for cancellation in 0..<4 {
            let recovery = makeRecovery()
            let id = pendingDocument(recovery)
            recovery.initializationFailed(in: "tab")
            switch cancellation {
            case 0: recovery.navigationStarted(in: "tab")
            case 1: recovery.navigationCancelled(in: "tab")
            case 2: recovery.invalidate()
            default: recovery.backgroundCompleted(id, succeeded: false)
            }
            recovery.backgroundCompleted(id, succeeded: true)
            await drain()
        }
        XCTAssertEqual(reloads, 0)
    }

    func testKillSwitchAndBackgroundStateAreRecheckedAtExecution() async {
        for suspendApplication in [false, true] {
            enabled = true
            backgrounded = false
            let recovery = makeRecovery()
            let id = pendingDocument(recovery)
            recovery.initializationFailed(in: "tab")
            recovery.backgroundCompleted(id, succeeded: true)
            if suspendApplication { backgrounded = true } else { enabled = false }
            await drain()
            XCTAssertEqual(reloads, 0)
        }
    }

    func testDisabledFlagDoesNotArmDocumentAndCanBeEnabledAtRuntime() async {
        let recovery = makeRecovery()
        enabled = false
        let id = pendingDocument(recovery)
        enabled = true
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertEqual(reloads, 0)
        let next = pendingDocument(recovery)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(next, succeeded: true)
        await drain()
        XCTAssertEqual(reloads, 1)
    }

    func testExpiredStartupAndUnsafeDocumentDoNotReloadOrClaimSuccess() async {
        let recovery = makeRecovery()
        let expired = pendingDocument(recovery)
        date.addTimeInterval(31)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(expired, succeeded: true)
        await drain()
        let unsafe = pendingDocument(recovery)
        recovery.registerDocument(in: "tab") { nil }
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(unsafe, succeeded: true)
        await drain()
        recovery.responseReceived(in: "tab")
        XCTAssertEqual(reloads, 0)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testOriginalResponseDuringReloadSafetyCheckCannotClaimRecovery() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.registerDocument(in: "tab") {
            recovery.responseReceived(in: "tab")
            return nil
        }
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testReplacementNavigationCannotClaimReloadResponse() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        recovery.navigationStarted(in: "tab")
        recovery.navigationCommitted(in: "tab", url: URL(string: "https://example.com/other")!)
        recovery.responseReceived(in: "tab")
        XCTAssertEqual(outcomes, [.reloadStarted])
    }

    func testUserNavigationDuringSafetyCheckCannotClaimRecovery() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        var safetyCheck: CheckedContinuation<CPMBackgroundReadinessRecovery.Reload?, Never>?
        recovery.registerDocument(in: "tab") { await withCheckedContinuation { safetyCheck = $0 } }
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        while safetyCheck == nil { await Task.yield() }
        recovery.navigationStarted(in: "tab")
        recovery.matchNavigationStarted(in: "tab") { _ in false }
        recovery.navigationCommitted(in: "tab", url: url)
        recovery.responseReceived(in: "tab")
        safetyCheck?.resume(returning: nil)
        await drain()
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testSameURLUserNavigationCannotClaimAcceptedReloadResponse() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        recovery.navigationStarted(in: "tab")
        recovery.matchNavigationStarted(in: "tab") { _ in false }
        recovery.navigationCommitted(in: "tab", url: url)
        recovery.responseReceived(in: "tab")
        XCTAssertEqual(outcomes, [.reloadStarted])
    }

    func testSafetyCheckRechecksFlagBackgroundDocumentAndDeadline() async {
        for invalidation in 0..<4 {
            enabled = true
            backgrounded = false
            date = Date()
            let recovery = makeRecovery()
            let id = pendingDocument(recovery)
            var completeCheck: CheckedContinuation<CPMBackgroundReadinessRecovery.Reload?, Never>?
            recovery.registerDocument(in: "tab") { await withCheckedContinuation { completeCheck = $0 } }
            recovery.initializationFailed(in: "tab")
            recovery.backgroundCompleted(id, succeeded: true)
            while completeCheck == nil { await Task.yield() }
            switch invalidation {
            case 0: enabled = false
            case 1: backgrounded = true
            case 2: recovery.navigationStarted(in: "tab")
            default: date.addTimeInterval(31)
            }
            completeCheck?.resume(returning: { [unowned self] in reloads += 1; return reloadNavigation })
            await drain()
            XCTAssertEqual(reloads, 0)
            XCTAssertTrue(outcomes.isEmpty)
        }
    }

    func testSynchronousMatchingReloadStartCanClaimResponse() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.registerDocument(in: "tab") { [reloadNavigation] in
            {
                recovery.navigationStarted(in: "tab")
                recovery.matchNavigationStarted(in: "tab") { $0 === reloadNavigation }
                return reloadNavigation
            }
        }
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        recovery.responseReceived(in: "tab")
        XCTAssertEqual(outcomes, [.reloadStarted, .responseReceived])
    }

    private func makeWebView(html: String, installSafety: Bool = true) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(RecoveryDocumentSchemeHandler(html: html), forURLScheme: "cpm-recovery-test")
        if installSafety {
            CPMDocumentRecoverySafety.install(in: configuration.userContentController)
            CPMDocumentRecoverySafety.install(in: configuration.userContentController)
            XCTAssertEqual(configuration.userContentController.userScripts.count, 1)
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.load(URLRequest(url: URL(string: "cpm-recovery-test://document")!))
        for _ in 0..<500 {
            if !view.isLoading { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(view.isLoading)
        _ = try XCTUnwrap(view.backForwardList.currentItem)
        return view
    }

    private func attemptRecovery(_ recovery: CPMBackgroundReadinessRecovery, webView: WKWebView) async throws {
        let startup = pendingDocument(recovery)
        recovery.registerDocument(in: "tab", webView: webView, isGET: true)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(startup, succeeded: true)
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    func testControlledAndShadowDraftsSurviveRecovery() async throws {
        for mode in ["controlled", "open", "closed"] {
            let view = try await makeWebView(html: """
                <!doctype html><html><body><div id="host"></div><script>
                const host = document.querySelector('#host');
                const root = '\(mode)' === 'controlled' ? host : host.attachShadow({mode: '\(mode)'});
                const field = document.createElement('input'); root.append(field);
                globalThis.editDraft = () => {
                    field.value = 'unsaved draft';
                    if ('\(mode)' === 'controlled') field.defaultValue = field.value;
                    if ('\(mode)' === 'closed') field.dispatchEvent(new Event('input', {bubbles:true, composed:true}));
                };
                globalThis.readDraft = () => field.value;
                </script></body></html>
                """)
            _ = try await view.evaluateJavaScript("editDraft()", in: nil, contentWorld: .page)
            let recovery = makeRecovery()
            try await attemptRecovery(recovery, webView: view)
            let draft = try await view.evaluateJavaScript("readDraft()", in: nil, contentWorld: .page) as? String
            XCTAssertEqual(draft, "unsaved draft", mode)
            XCTAssertTrue(outcomes.isEmpty, mode)
        }
    }

    func testInteractionStillVetoesAfterFieldIsRemoved() async throws {
        let view = try await makeWebView(html: "<html><body><input></body></html>")
        _ = try await view.evaluateJavaScript("""
            document.querySelector('input').dispatchEvent(new Event('input', {bubbles:true, composed:true}));
            document.querySelector('input').remove();
            """, in: nil, contentWorld: .page)
        try await attemptRecovery(makeRecovery(), webView: view)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testMissingDocumentStartSafetyVetoesRecovery() async throws {
        let view = try await makeWebView(html: "<html><body>Pristine</body></html>", installSafety: false)
        try await attemptRecovery(makeRecovery(), webView: view)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testPristineInstrumentedDocumentCanStillReload() async throws {
        let view = try await makeWebView(html: "<html><body>Pristine</body></html>")
        let recovery = makeRecovery()
        try await attemptRecovery(recovery, webView: view)
        XCTAssertEqual(outcomes, [.reloadStarted])
    }

    func testEveryFixHasSeparatePIIFreeMetadata() {
        for fix in CPMRecoveryFix.allCases {
            let outcome: CPMRecoveryOutcome = fix == .lateDocumentReload ? .reloadStarted : .backgroundReady
            let metadata = CPMWebExtensionPixelMetadata(event: .cpmRecovery(fix, outcome: outcome))
            XCTAssertEqual(metadata?.name, "web_extension_cpm_\(fix.rawValue)")
            XCTAssertEqual(metadata?.frequency, .dailyAndCount)
            XCTAssertEqual(metadata?.parameters, ["outcome": outcome.rawValue])
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private struct Instrumentation: CPMRecoveryInstrumentation {
    let callback: (CPMRecoveryOutcome) -> Void
    func record(_ fix: CPMRecoveryFix, outcome: CPMRecoveryOutcome) {
        XCTAssertEqual(fix, .lateDocumentReload)
        callback(outcome)
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class RecoveryDocumentSchemeHandler: NSObject, WKURLSchemeHandler {
    private let html: String

    init(html: String) { self.html = html }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let data = Data(html.utf8)
        urlSchemeTask.didReceive(URLResponse(url: urlSchemeTask.request.url!, mimeType: "text/html",
                                            expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
