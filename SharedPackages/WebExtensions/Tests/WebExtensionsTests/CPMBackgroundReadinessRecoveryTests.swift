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
    private let pixelFiring = CapturingRecoveryPixelFiring()
    private var outcomes: [CPMRecoveryOutcome] { pixelFiring.outcomes }
    private var detections: Int { pixelFiring.detections }

    private func makeRecovery() -> CPMBackgroundReadinessRecovery {
        CPMBackgroundReadinessRecovery(isEnabled: { [unowned self] in enabled },
                                       isApplicationInBackground: { [unowned self] in backgrounded },
                                       pixelFiring: pixelFiring,
                                       now: { [unowned self] in date })
    }

    private func pendingDocument(_ recovery: CPMBackgroundReadinessRecovery, isFirstLoad: Bool = false) -> UUID {
        let id = UUID()
        recovery.backgroundStarted(id, isFirstLoad: isFirstLoad)
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

    func testDisabledFlagDetectsWithoutRetroactiveReloadAndCanBeEnabledAtRuntime() async {
        let recovery = makeRecovery()
        enabled = false
        let id = pendingDocument(recovery, isFirstLoad: true)
        enabled = true
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertEqual(reloads, 0)
        XCTAssertEqual(detections, 1)
        let next = pendingDocument(recovery, isFirstLoad: true)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(next, succeeded: true)
        await drain()
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(detections, 2)
    }

    func testFirstStartupIsDetectedOnceWithRecoveryDisabledWithoutCallingPreflight() async {
        enabled = false
        let recovery = makeRecovery()
        let id = pendingDocument(recovery, isFirstLoad: true)
        recovery.registerDocument(in: "tab") {
            XCTFail("Detection must not evaluate document safety or request a reload")
            return nil
        }
        recovery.initializationFailed(in: "tab")
        XCTAssertEqual(detections, 0, "Successful background startup is still required")
        recovery.backgroundCompleted(id, succeeded: true)
        recovery.backgroundCompleted(id, succeeded: true)
        recovery.initializationFailed(in: "tab")
        await drain()
        XCTAssertEqual(detections, 1)
        XCTAssertEqual(reloads, 0)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testFirstStartupIsDetectedWhenFailureArrivesAfterReadinessWithoutReloadClosure() async {
        enabled = false
        let recovery = makeRecovery()
        let id = UUID()
        recovery.backgroundStarted(id, isFirstLoad: true)
        recovery.navigationStarted(in: "tab")
        recovery.navigationCommitted(in: "tab", url: url)
        recovery.backgroundCompleted(id, succeeded: true)
        XCTAssertEqual(detections, 0)
        recovery.initializationFailed(in: "tab")
        await drain()
        XCTAssertEqual(detections, 1)
        XCTAssertEqual(reloads, 0)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testIdleWakeDoesNotCountAsFirstStartupDetection() async {
        enabled = false
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertEqual(detections, 0)
        XCTAssertEqual(reloads, 0)
    }

    func testFirstStartupCountsEachFailedDocumentOnlyOnce() async {
        enabled = false
        let recovery = makeRecovery()
        let id = UUID()
        recovery.backgroundStarted(id, isFirstLoad: true)
        for tab in ["first", "second"] {
            recovery.navigationStarted(in: tab)
            recovery.navigationCommitted(in: tab, url: url)
            recovery.initializationFailed(in: tab)
        }
        recovery.backgroundCompleted(id, succeeded: true)
        recovery.backgroundCompleted(id, succeeded: true)
        for tab in ["first", "second"] { recovery.initializationFailed(in: tab) }
        await drain()
        XCTAssertEqual(detections, 2)
        XCTAssertEqual(reloads, 0)
    }

    func testHealthyInvalidatedFailedAndExpiredFirstStartupDocumentsAreNotDetected() async {
        enabled = false
        for invalidation in 0..<6 {
            date = Date()
            let recovery = makeRecovery()
            let id = pendingDocument(recovery, isFirstLoad: true)
            switch invalidation {
            case 0: recovery.responseReceived(in: "tab")
            case 1: recovery.navigationStarted(in: "tab")
            case 2: recovery.navigationCancelled(in: "tab")
            case 3: recovery.invalidate()
            case 4: recovery.backgroundCompleted(id, succeeded: false)
            default: date.addTimeInterval(31)
            }
            recovery.initializationFailed(in: "tab")
            recovery.backgroundCompleted(id, succeeded: true)
            await drain()
            XCTAssertEqual(detections, 0)
            XCTAssertEqual(reloads, 0)
        }
    }

    func testDetectionAndRecoveryHaveIndependentOutcomes() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery, isFirstLoad: true)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertEqual(detections, 1)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(outcomes, [.reloadStarted])
        recovery.navigationStarted(in: "tab")
        recovery.matchNavigationStarted(in: "tab") { [reloadNavigation] in $0 === reloadNavigation }
        recovery.responseReceived(in: "tab")
        XCTAssertEqual(detections, 1)
        XCTAssertEqual(outcomes, [.reloadStarted, .responseReceived])
    }

    func testDetectionHasSeparatePIIFreeDailyCountMetadata() {
        let metadata = CPMWebExtensionPixelMetadata(event: .cpmStartupResponseMissing)
        XCTAssertEqual(metadata?.name, "web_extension_cpm_startup_response_missing")
        XCTAssertEqual(metadata?.frequency, .dailyAndCount)
        XCTAssertEqual(metadata?.parameters, [:])
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

    func testEveryFixHasSeparatePIIFreeMetadata() {
        for fix in CPMRecoveryFix.allCases {
            let outcome: CPMRecoveryOutcome = fix == .lateDocumentReload ? .reloadStarted : .backgroundReady
            let metadata = CPMWebExtensionPixelMetadata(event: .cpmRecovery(fix, outcome: outcome))
            XCTAssertEqual(metadata?.name, "web_extension_cpm_\(fix.rawValue)")
            XCTAssertEqual(metadata?.frequency, .dailyAndCount)
            XCTAssertEqual(metadata?.parameters, ["outcome": outcome.rawValue])
        }
    }

    func testRealWebViewDoesNotReloadEditedInput() async throws {
        try await assertRealDocumentRecovery(html: "<input id='draft'>",
                                             edit: "document.querySelector('#draft').value = 'unsaved'; true",
                                             expectsReload: false)
    }

    func testRealWebViewDoesNotReloadEditedIframeAfterFocusLeavesIt() async throws {
        try await assertRealDocumentRecovery(html: "<iframe srcdoc=\"<input id='draft'>\"></iframe>",
                                             edit: """
                                             const frame = document.querySelector('iframe');
                                             const input = frame.contentDocument.querySelector('input');
                                             input.value = 'unsaved';
                                             input.focus();
                                             input.blur();
                                             document.body.tabIndex = -1;
                                             document.body.focus();
                                             document.activeElement === document.body
                                             """,
                                             expectsReload: false)
    }

    func testRealWebViewDoesNotReloadFocusedShadowInput() async throws {
        try await assertRealDocumentRecovery(html: "<div id='host'></div>",
                                             edit: """
                                             const host = document.querySelector('#host');
                                             const shadow = host.attachShadow({ mode: 'open' });
                                             shadow.innerHTML = '<input>';
                                             const input = shadow.querySelector('input');
                                             input.value = 'unsaved';
                                             input.focus();
                                             document.activeElement === host
                                             """,
                                             expectsReload: false)
    }

    func testRealWebViewDoesNotReloadNonGETDocument() async throws {
        try await assertRealDocumentRecovery(html: "<p>Pristine document</p>", isGET: false, expectsReload: false)
    }

    func testRealWebViewReloadsPristineGETDocument() async throws {
        try await assertRealDocumentRecovery(html: "<input value='unchanged'>", expectsReload: true)
    }

    private func assertRealDocumentRecovery(html: String, edit: String? = nil, isGET: Bool = true,
                                            expectsReload: Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let loaded = expectation(description: "Fixture document loaded")
        let navigationDelegate = RecoveryDocumentNavigationDelegate(loaded: loaded)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(RecoveryDocumentSchemeHandler(html: html), forURLScheme: "cpm-recovery-test")
        let webView = RecoveryDocumentWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        webView.navigationDelegate = navigationDelegate
        webView.load(URLRequest(url: URL(string: "cpm-recovery-test://document")!))
        await fulfillment(of: [loaded], timeout: 5)
        XCTAssertFalse(webView.isLoading, file: file, line: line)
        XCTAssertNotNil(webView.backForwardList.currentItem, file: file, line: line)
        if let edit {
            let edited = try await webView.evaluateJavaScript(edit, in: nil, contentWorld: .page) as? Bool
            XCTAssertEqual(edited, true, "Fixture must reach its intended edited/focused state", file: file, line: line)
        }

        let reload = expectation(description: "Production recovery requests reload")
        reload.isInverted = !expectsReload
        webView.onReload = { reload.fulfill() }
        let reloaded = expectsReload ? expectation(description: "Recovery navigation finishes") : nil
        navigationDelegate.onSubsequentFinish = { reloaded?.fulfill() }
        let recovery = makeRecovery()
        let startup = UUID()
        recovery.backgroundStarted(startup, isFirstLoad: true)
        recovery.navigationCommitted(in: "tab", url: url)
        recovery.registerDocument(in: "tab", webView: webView, isGET: isGET)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(startup, succeeded: true)
        await fulfillment(of: [reload] + (reloaded.map { [$0] } ?? []), timeout: expectsReload ? 5 : 1)
        XCTAssertEqual(webView.reloadCount, expectsReload ? 1 : 0, file: file, line: line)
        XCTAssertEqual(detections, 1, "Detection must remain independent of the reload veto", file: file, line: line)
        XCTAssertEqual(outcomes, expectsReload ? [.reloadStarted] : [], file: file, line: line)
        withExtendedLifetime(navigationDelegate) {}
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class RecoveryDocumentWebView: WKWebView {
    var onReload: (() -> Void)?
    private(set) var reloadCount = 0

    override func reload() -> WKNavigation? {
        reloadCount += 1
        let navigation = super.reload()
        onReload?()
        return navigation
    }
}

@MainActor
private final class RecoveryDocumentSchemeHandler: NSObject, WKURLSchemeHandler {
    private let html: Data

    init(html: String) { self.html = Data(html.utf8) }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let response = URLResponse(url: urlSchemeTask.request.url!, mimeType: "text/html",
                                   expectedContentLength: html.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(html)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

@MainActor
private final class RecoveryDocumentNavigationDelegate: NSObject, WKNavigationDelegate {
    private let loaded: XCTestExpectation
    private var didFinishInitialLoad = false
    var onSubsequentFinish: (() -> Void)?

    init(loaded: XCTestExpectation) { self.loaded = loaded }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if didFinishInitialLoad {
            onSubsequentFinish?()
        } else {
            didFinishInitialLoad = true
            loaded.fulfill()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        XCTFail("Fixture navigation failed: \(error)")
        loaded.fulfill()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        XCTFail("Fixture provisional navigation failed: \(error)")
        loaded.fulfill()
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class CapturingRecoveryPixelFiring: WebExtensionPixelFiring {
    private(set) var outcomes: [CPMRecoveryOutcome] = []
    private(set) var detections = 0

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .cpmRecovery(let fix, let outcome):
            XCTAssertEqual(fix, .lateDocumentReload)
            outcomes.append(outcome)
        case .cpmStartupResponseMissing:
            detections += 1
        default:
            XCTFail("Unexpected recovery pixel: \(event)")
        }
    }
}
