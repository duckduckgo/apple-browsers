//
//  CPMBackgroundWebViewDelegateProxyTests.swift
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

import WebKit
import XCTest
@testable import WebExtensions

/// Stands in for WebKit's `_WKWebExtensionContextDelegate`: implements only the public termination callback plus one
/// unrelated navigation callback, like the real one.
@MainActor
private final class OriginalDelegate: NSObject, WKNavigationDelegate {
    var terminatedCalls = 0
    var didCommitCalls = 0

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        terminatedCalls += 1
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        didCommitCalls += 1
    }
}

/// An original that also implements the private reason variant, to check the proxy prefers it when forwarding.
@MainActor
private final class OriginalDelegateWithReason: NSObject, WKNavigationDelegate {
    var reasons: [Int] = []
    var publicCalls = 0

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        publicCalls += 1
    }

    @objc(_webView:webContentProcessDidTerminateWithReason:)
    func webView(_ webView: WKWebView, webContentProcessDidTerminateWithReason reason: Int) {
        reasons.append(reason)
    }
}

@MainActor
private final class Delegate: CPMBackgroundWebViewProxyDelegate {
    var terminations: [CPMBackgroundProcessTerminationReason?] = []
    var unresponsiveCalls = 0
    var responsiveCalls = 0

    func backgroundWebView(_ webView: WKWebView, webContentProcessDidTerminateWith reason: CPMBackgroundProcessTerminationReason?) {
        terminations.append(reason)
    }
    func backgroundWebViewWebProcessDidBecomeUnresponsive(_ webView: WKWebView) { unresponsiveCalls += 1 }
    func backgroundWebViewWebProcessDidBecomeResponsive(_ webView: WKWebView) { responsiveCalls += 1 }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundWebViewDelegateProxyTests: XCTestCase {

    private let terminatedWithReason = NSSelectorFromString("_webView:webContentProcessDidTerminateWithReason:")
    private let becameUnresponsive = NSSelectorFromString("_webViewWebProcessDidBecomeUnresponsive:")
    private let becameResponsive = NSSelectorFromString("_webViewWebProcessDidBecomeResponsive:")

    func testInstallWrapsExistingDelegateAndIsIdempotent() {
        let webView = WKWebView(frame: .zero)
        let original = OriginalDelegate()
        let delegate = Delegate()
        webView.navigationDelegate = original

        let proxy = CPMBackgroundWebViewDelegateProxy.install(on: webView, delegate: delegate)
        XCTAssertNotNil(proxy)
        XCTAssertTrue(webView.navigationDelegate === proxy)
        XCTAssertTrue(CPMBackgroundWebViewDelegateProxy.isInstalled(on: webView))

        let again = CPMBackgroundWebViewDelegateProxy.install(on: webView, delegate: delegate)
        XCTAssertTrue(again === proxy, "second install must not stack proxies")
        XCTAssertTrue(webView.navigationDelegate === proxy)
    }

    func testUninstallRestoresOriginalDelegateAndReinstallReusesProxy() {
        let webView = WKWebView(frame: .zero)
        let original = OriginalDelegate()
        webView.navigationDelegate = original

        weak var proxy: CPMBackgroundWebViewDelegateProxy?
        autoreleasepool {
            proxy = CPMBackgroundWebViewDelegateProxy.install(on: webView, delegate: Delegate())
            XCTAssertNotNil(proxy)
            CPMBackgroundWebViewDelegateProxy.uninstall(from: webView)
        }

        XCTAssertTrue(webView.navigationDelegate === original)
        XCTAssertFalse(CPMBackgroundWebViewDelegateProxy.isInstalled(on: webView))
        XCTAssertNotNil(proxy)

        let delegate = Delegate()
        let reinstalled = CPMBackgroundWebViewDelegateProxy.install(on: webView, delegate: delegate)
        XCTAssertTrue(reinstalled === proxy)
        reinstalled?.webViewWebContentProcessDidTerminate(webView)
        XCTAssertEqual(delegate.terminations, [nil])
    }

    func testUninstalledProxyIsReleasedWithOriginalDelegate() {
        let webView = WKWebView(frame: .zero)
        weak var weakOriginal: OriginalDelegate?
        weak var proxy: CPMBackgroundWebViewDelegateProxy?
        autoreleasepool {
            let original = OriginalDelegate()
            weakOriginal = original
            webView.navigationDelegate = original
            proxy = CPMBackgroundWebViewDelegateProxy.install(on: webView, delegate: Delegate())
            CPMBackgroundWebViewDelegateProxy.uninstall(from: webView)
            XCTAssertNotNil(proxy)
            XCTAssertTrue(webView.navigationDelegate === original)
        }

        XCTAssertNil(weakOriginal)
        XCTAssertNil(proxy)
        XCTAssertNil(webView.navigationDelegate)
    }

    func testInstallWithoutOriginalDelegateIsSkipped() {
        let webView = WKWebView(frame: .zero)
        XCTAssertNil(CPMBackgroundWebViewDelegateProxy.install(on: webView, delegate: Delegate()))
        XCTAssertNil(webView.navigationDelegate)
        XCTAssertFalse(CPMBackgroundWebViewDelegateProxy.isInstalled(on: webView))
    }

    func testInstalledProxyIsReleasedWithOriginalDelegate() {
        let webView = WKWebView(frame: .zero)
        weak var weakOriginal: OriginalDelegate?
        weak var proxy: CPMBackgroundWebViewDelegateProxy?
        autoreleasepool {
            let original = OriginalDelegate()
            weakOriginal = original
            webView.navigationDelegate = original
            proxy = CPMBackgroundWebViewDelegateProxy.install(on: webView, delegate: Delegate())
            XCTAssertNotNil(proxy)
        }

        XCTAssertNil(weakOriginal)
        XCTAssertNil(proxy)
        XCTAssertNil(webView.navigationDelegate)
        XCTAssertFalse(CPMBackgroundWebViewDelegateProxy.isInstalled(on: webView))
    }

    func testUninstallDoesNotRemoveProxyFromAnotherViewSharingOriginal() {
        let original = OriginalDelegate()
        let first = WKWebView(frame: .zero)
        let second = WKWebView(frame: .zero)
        first.navigationDelegate = original
        second.navigationDelegate = original
        weak var proxy: CPMBackgroundWebViewDelegateProxy?
        autoreleasepool {
            proxy = CPMBackgroundWebViewDelegateProxy.install(on: first, delegate: Delegate())
            CPMBackgroundWebViewDelegateProxy.install(on: second, delegate: Delegate())

            CPMBackgroundWebViewDelegateProxy.uninstall(from: first)

            XCTAssertTrue(first.navigationDelegate === original)
            XCTAssertNotNil(proxy)
            XCTAssertTrue(second.navigationDelegate === proxy)
            XCTAssertTrue(CPMBackgroundWebViewDelegateProxy.isInstalled(on: second))

            CPMBackgroundWebViewDelegateProxy.uninstall(from: second)
        }

        XCTAssertTrue(second.navigationDelegate === original)
        XCTAssertFalse(CPMBackgroundWebViewDelegateProxy.isInstalled(on: second))
        XCTAssertNotNil(proxy)
    }

    func testRespondsToOriginalMethodsAndObservedSelectorsOnly() {
        let original = OriginalDelegate()
        let proxy = CPMBackgroundWebViewDelegateProxy(original: original, delegate: Delegate())

        // Original's methods are visible through the proxy — WebKit decides which callbacks to send from these answers.
        XCTAssertTrue(proxy.responds(to: #selector(WKNavigationDelegate.webView(_:didCommit:))))
        XCTAssertTrue(proxy.responds(to: #selector(WKNavigationDelegate.webViewWebContentProcessDidTerminate(_:))))
        // Added by the proxy.
        XCTAssertTrue(proxy.responds(to: terminatedWithReason))
        XCTAssertTrue(proxy.responds(to: becameUnresponsive))
        XCTAssertTrue(proxy.responds(to: becameResponsive))
        // Not implemented by either.
        XCTAssertFalse(proxy.responds(to: #selector(WKNavigationDelegate.webView(_:didFinish:))))
        XCTAssertFalse(proxy.responds(to: NSSelectorFromString("_webViewWebProcessDidCrash:")))
    }

    func testUnrelatedCallbacksAreForwardedToOriginal() {
        let webView = WKWebView(frame: .zero)
        let original = OriginalDelegate()
        let proxy = CPMBackgroundWebViewDelegateProxy(original: original, delegate: Delegate())

        (proxy as WKNavigationDelegate).webView?(webView, didCommit: nil)

        XCTAssertEqual(original.didCommitCalls, 1)
    }

    func testPublicTerminationNotifiesDelegateAndForwards() {
        let webView = WKWebView(frame: .zero)
        let original = OriginalDelegate()
        let delegate = Delegate()
        let proxy = CPMBackgroundWebViewDelegateProxy(original: original, delegate: delegate)

        proxy.webViewWebContentProcessDidTerminate(webView)

        XCTAssertEqual(delegate.terminations, [nil])
        XCTAssertEqual(original.terminatedCalls, 1)
    }

    func testPrivateTerminationWithReasonFallsBackToOriginalPublicMethod() {
        let webView = WKWebView(frame: .zero)
        let original = OriginalDelegate()
        let delegate = Delegate()
        let proxy = CPMBackgroundWebViewDelegateProxy(original: original, delegate: delegate)

        proxy.webView(webView, webContentProcessDidTerminateWithReason: 3)

        XCTAssertEqual(delegate.terminations, [.crash])
        XCTAssertEqual(original.terminatedCalls, 1, "WebKit calls only the private variant on the proxy; the original must still get its public callback")
    }

    func testPrivateTerminationWithReasonPrefersOriginalPrivateMethod() {
        let webView = WKWebView(frame: .zero)
        let original = OriginalDelegateWithReason()
        let delegate = Delegate()
        let proxy = CPMBackgroundWebViewDelegateProxy(original: original, delegate: delegate)

        proxy.webView(webView, webContentProcessDidTerminateWithReason: 0)

        XCTAssertEqual(delegate.terminations, [.exceededMemoryLimit])
        XCTAssertEqual(original.reasons, [0])
        XCTAssertEqual(original.publicCalls, 0)
    }

    func testTerminationReasonMapping() {
        XCTAssertEqual(CPMBackgroundProcessTerminationReason(rawValue: 0), .exceededMemoryLimit)
        XCTAssertEqual(CPMBackgroundProcessTerminationReason(rawValue: 1), .exceededCPULimit)
        XCTAssertEqual(CPMBackgroundProcessTerminationReason(rawValue: 2), .requestedByClient)
        XCTAssertEqual(CPMBackgroundProcessTerminationReason(rawValue: 3), .crash)
        XCTAssertEqual(CPMBackgroundProcessTerminationReason(rawValue: 4), .exceededSharedProcessCrashLimit)
        XCTAssertNil(CPMBackgroundProcessTerminationReason(rawValue: 42))
        XCTAssertEqual((0...4).compactMap { CPMBackgroundProcessTerminationReason(rawValue: $0)?.description },
                       ["memory", "cpu", "client", "crash", "crash_limit"])
    }

    func testResponsivenessCallbacksReachDelegateEvenWhenOriginalLacksThem() {
        let webView = WKWebView(frame: .zero)
        let delegate = Delegate()
        let proxy = CPMBackgroundWebViewDelegateProxy(original: OriginalDelegate(), delegate: delegate)

        proxy.webViewWebProcessDidBecomeUnresponsive(webView)
        proxy.webViewWebProcessDidBecomeResponsive(webView)

        XCTAssertEqual(delegate.unresponsiveCalls, 1)
        XCTAssertEqual(delegate.responsiveCalls, 1)
    }

    func testMissingOriginalStillNotifiesDelegate() {
        let webView = WKWebView(frame: .zero)
        let delegate = Delegate()
        let proxy = CPMBackgroundWebViewDelegateProxy(original: nil, delegate: delegate)

        XCTAssertFalse(proxy.responds(to: #selector(WKNavigationDelegate.webView(_:didCommit:))))
        proxy.webViewWebContentProcessDidTerminate(webView)
        proxy.webView(webView, webContentProcessDidTerminateWithReason: 1)
        XCTAssertEqual(delegate.terminations, [nil, .exceededCPULimit])
    }

    func testProxyDoesNotRetainOriginal() {
        var original: OriginalDelegate? = OriginalDelegate()
        weak var weakOriginal = original
        let proxy = CPMBackgroundWebViewDelegateProxy(original: original, delegate: Delegate())
        original = nil

        XCTAssertNil(weakOriginal)
        withExtendedLifetime(proxy) {}
    }

    func testRecorderRecordsTerminationTimeline() async throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { clock })
        let webView = WKWebView(frame: .zero)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        recorder.didCreateBackgroundWebView(webView, for: context)

        recorder.backgroundWebView(webView, webContentProcessDidTerminateWith: .crash)
        clock = clock.addingTimeInterval(42)
        var parameters = recorder.snapshot().pixelParameters
        XCTAssertEqual(parameters[CPMMessagingDiagnostics.ParameterName.backgroundEvents], "load@-42,view@-42,died_crash@-42")

        // Responsiveness callbacks for a view that is not the current one are ignored.
        recorder.backgroundWebViewWebProcessDidBecomeUnresponsive(WKWebView(frame: .zero))
        parameters = recorder.snapshot().pixelParameters
        XCTAssertEqual(parameters[CPMMessagingDiagnostics.ParameterName.backgroundEvents], "load@-42,view@-42,died_crash@-42")
    }

    func testWhenProxyDisabledThenAllSurvivingViewDelegatesAreRestored() async throws {
        let flags = CPMDiagnosticsStaticFeatureFlags()
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, featureFlags: flags)
        let context = try await makeContext()
        let original = OriginalDelegate()
        let oldView = WKWebView(frame: .zero)
        let currentView = WKWebView(frame: .zero)
        oldView.navigationDelegate = original
        currentView.navigationDelegate = original
        recorder.contextWillLoad(context)
        recorder.didCreateBackgroundWebView(oldView, for: context)
        recorder.didCreateBackgroundWebView(currentView, for: context)

        flags.isBackgroundDelegateProxyEnabled = false
        recorder.applyFeatureFlags()

        XCTAssertTrue(oldView.navigationDelegate === original)
        XCTAssertTrue(currentView.navigationDelegate === original)

        flags.isBackgroundDelegateProxyEnabled = true
        recorder.applyFeatureFlags()
        XCTAssertTrue(oldView.navigationDelegate === original)
        XCTAssertTrue(CPMBackgroundWebViewDelegateProxy.isInstalled(on: currentView))
    }

    func testWhenProxyDisabledAfterUnloadThenSurvivingViewDelegateIsRestored() async throws {
        let flags = CPMDiagnosticsStaticFeatureFlags()
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, featureFlags: flags)
        let context = try await makeContext()
        let original = OriginalDelegate()
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = original
        recorder.contextWillLoad(context)
        recorder.didCreateBackgroundWebView(view, for: context)
        recorder.contextDidUnload(identifier: context.uniqueIdentifier)

        flags.isBackgroundDelegateProxyEnabled = false
        recorder.applyFeatureFlags()

        XCTAssertTrue(view.navigationDelegate === original)
        flags.isBackgroundDelegateProxyEnabled = true
        recorder.applyFeatureFlags()
        XCTAssertTrue(view.navigationDelegate === original)
        recorder.backgroundWebView(view, webContentProcessDidTerminateWith: .crash)
        XCTAssertFalse(recorder.snapshot().backgroundEvents.contains { $0.token == "died_crash" })
    }

    func testProxyFollowsFeatureFlagAtRuntime() async throws {
        let flags = CPMDiagnosticsStaticFeatureFlags(isBackgroundDelegateProxyEnabled: true)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, featureFlags: flags)
        let webView = WKWebView(frame: .zero)
        let original = OriginalDelegate()
        webView.navigationDelegate = original

        // Simulate WebKit's callback for a background view of the CPM context.
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        recorder.didCreateBackgroundWebView(webView, for: context)
        XCTAssertTrue(CPMBackgroundWebViewDelegateProxy.isInstalled(on: webView))
        XCTAssertTrue(webView.navigationDelegate is CPMBackgroundWebViewDelegateProxy)

        // Flag turned off at runtime: the original delegate must be handed back.
        flags.isBackgroundDelegateProxyEnabled = false
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(CPMBackgroundWebViewDelegateProxy.isInstalled(on: webView))
        XCTAssertTrue(webView.navigationDelegate === original)

        // And back on: re-installed on the current view.
        flags.isBackgroundDelegateProxyEnabled = true
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(CPMBackgroundWebViewDelegateProxy.isInstalled(on: webView))

        let events = recorder.snapshot().pixelParameters[CPMMessagingDiagnostics.ParameterName.backgroundEvents] ?? ""
        XCTAssertTrue(events.contains("proxy_on@"), events)
        XCTAssertTrue(events.contains("proxy_off@"), events)
    }

    func testProxyNotInstalledWhenFlagIsOff() async throws {
        let flags = CPMDiagnosticsStaticFeatureFlags(isBackgroundDelegateProxyEnabled: false)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, featureFlags: flags)
        let webView = WKWebView(frame: .zero)
        let original = OriginalDelegate()
        webView.navigationDelegate = original

        let context = try await makeContext()
        recorder.contextWillLoad(context)
        recorder.didCreateBackgroundWebView(webView, for: context)

        XCTAssertFalse(CPMBackgroundWebViewDelegateProxy.isInstalled(on: webView))
        XCTAssertTrue(webView.navigationDelegate === original)
    }

    /// Minimal on-disk extension so a real `WKWebExtensionContext` can be created; mirrors `CPMMessagingDiagnosticsTests`.
    private func makeContext() async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CPMProxyTestExtension-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let manifest = """
        {
            "manifest_version": 3,
            "name": "CPM Proxy Test Extension",
            "version": "1.0.0",
            "background": { "service_worker": "background.js" }
        }
        """
        try manifest.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "// test".write(to: directory.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)
        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = "cpm-proxy-test"
        return context
    }
}
