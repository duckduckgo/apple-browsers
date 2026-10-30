//
//  CPMErrorPageMonitoringTests.swift
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

import Combine
import Common
import DDGNavigation
import MaliciousSiteProtection
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import WebExtensions
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// A failed load is shown as the app's own error page, loaded as alternate HTML for the failed http(s) URL.
/// That document never runs content scripts, so the CPM health monitor must be told it is an error page
/// and not measure it; otherwise every error page after an idle background unload is counted as a CPM failure.
@available(macOS 15.4, *)
final class CPMErrorPageMonitoringTests: XCTestCase {

    private let failedURL = URL(string: "https://testhost.com/")!

    private var contentBlockingMock: ContentBlockingMock!
    private var privacyFeaturesMock: AnyPrivacyFeatures!
    private var schemeHandler: TestSchemeHandler!
    private var window: NSWindow!

    private var privacyConfiguration: MockPrivacyConfiguration {
        contentBlockingMock.privacyConfigurationManager.privacyConfig as! MockPrivacyConfiguration
    }

    override func setUp() {
        contentBlockingMock = ContentBlockingMock()
        privacyFeaturesMock = AppPrivacyFeatures(contentBlocking: contentBlockingMock, httpsUpgradeStore: HTTPSUpgradeStoreMock())
        // disable waiting for CBR compilation on navigation
        privacyConfiguration.isFeatureEnabledCheck = { _, _ in
            return false
        }
        schemeHandler = TestSchemeHandler { _ in
            return .ok(.html(""))
        }
    }

    @MainActor
    override func tearDown() async throws {
        window?.close()
        window = nil

        contentBlockingMock = nil
        privacyFeaturesMock = nil
        schemeHandler = nil
    }

    @MainActor
    func testErrorPageAfterFailedLoadIsReportedToHealthMonitorAsErrorPage() async throws {
        try await assertErrorPageIsReportedAsErrorPage(failure: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost),
                                                       expectedErrorCode: NSURLErrorCannotFindHost)
    }

    /// The special SSL error page is also loaded as alternate HTML for the failed URL.
    @MainActor
    func testSSLErrorPageIsReportedToHealthMonitorAsErrorPage() async throws {
        try await assertErrorPageIsReportedAsErrorPage(failure: NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted),
                                                       expectedErrorCode: NSURLErrorServerCertificateUntrusted)
    }

    /// A malicious site is redirected to a `duck://error` navigation that fails with `MaliciousSiteError`;
    /// the warning page is then loaded as alternate HTML for the malicious URL.
    @MainActor
    func testMaliciousSiteWarningPageIsReportedToHealthMonitorAsErrorPage() async throws {
        let detector = MockMaliciousSiteProtectionManager()
        detector.threatKind = .phishing
        let monitor = RecordingCPMHealthMonitor()
        let manager = StubWebExtensionManager(monitor: monitor)
        let tab = Tab(content: .none,
                      webViewConfiguration: schemeHandler.webViewConfiguration(),
                      privacyFeatures: privacyFeaturesMock,
                      maliciousSiteDetector: detector,
                      webExtensionManagerProvider: { manager })
        window = WindowsManager.openNewWindow(with: tab)!
        schemeHandler.middleware = [{ _ in .ok(.html("")) }]
        let eNavigationFailed = tab.$error
            .compactMap { $0 }
            .timeout(5)
            .first()
            .promise()

        tab.setContent(.contentFromURL(failedURL, source: .link))

        let error = try await eNavigationFailed.value
        XCTAssertEqual((error as NSError).domain, "MaliciousSiteError", "expected the malicious site error, got \(error)")
        let reported = await waitUntil(timeout: 5) { monitor.events.last?.hasPrefix("finished:") == true }
        XCTAssertTrue(reported, "the warning page finish was not reported to the monitor: \(monitor.events)")
        assertErrorPageEvents(monitor.events)
    }

    @MainActor
    private func assertErrorPageIsReportedAsErrorPage(failure: NSError, expectedErrorCode: Int) async throws {
        let monitor = RecordingCPMHealthMonitor()
        let manager = StubWebExtensionManager(monitor: monitor)
        let tab = Tab(content: .none,
                      webViewConfiguration: schemeHandler.webViewConfiguration(),
                      privacyFeatures: privacyFeaturesMock,
                      webExtensionManagerProvider: { manager })
        window = WindowsManager.openNewWindow(with: tab)!

        schemeHandler.middleware = [{ _ in .failure(failure) }]
        let eNavigationFailed = tab.$error
            .compactMap { $0 }
            .timeout(3)
            .first()
            .promise()
        // error page navigation
        let eNavigationDidFinish = tab.webViewDidFinishNavigationPublisher
            .timeout(3)
            .first()
            .promise()

        tab.setContent(.contentFromURL(failedURL, source: .link))

        let error = try await eNavigationFailed.value
        _ = try await eNavigationDidFinish.value
        XCTAssertEqual(error.errorCode, expectedErrorCode)

        let reported = await waitUntil(timeout: 5) { monitor.events.last?.hasPrefix("finished:") == true }
        XCTAssertTrue(reported, "the error page finish was not reported to the monitor: \(monitor.events)")
        assertErrorPageEvents(monitor.events)
    }

    /// After the failed load the error page starts as `.errorPage`, and the failed URL is committed and finished
    /// only as part of it, so the monitor never measures it.
    @MainActor
    private func assertErrorPageEvents(_ events: [String], file: StaticString = #filePath, line: UInt = #line) {
        let lastStart = events.lastIndex { $0.hasPrefix("started:") }
        XCTAssertEqual(lastStart.map { events[$0] }, "started:error_page",
                       "the error page must start as .errorPage: \(events)", file: file, line: line)
        let failedIndex = events.firstIndex(of: "failed")
        XCTAssertNotNil(failedIndex, "the load must fail before the error page: \(events)", file: file, line: line)
        XCTAssertTrue((failedIndex ?? .max) < (lastStart ?? 0), "the load must fail before the error page starts: \(events)", file: file, line: line)
        let afterErrorStart = events.suffix(from: lastStart ?? 0)
        XCTAssertTrue(afterErrorStart.contains("finished:\(failedURL.absoluteString)"),
                      "the error page reports the failed URL, which the monitor must not measure: \(events)", file: file, line: line)
        let beforeErrorStart = events.prefix(upTo: lastStart ?? 0)
        XCTAssertFalse(beforeErrorStart.contains { $0.hasPrefix("finished:") },
                       "the failed URL must not finish as an ordinary navigation: \(events)", file: file, line: line)
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
}

/// Records the navigation events a tab sends to the CPM health monitor.
@available(macOS 15.4, *)
private final class RecordingCPMHealthMonitor: CPMMessagingHealthMonitoring, @unchecked Sendable {

    @MainActor private(set) var events: [String] = []

    @MainActor
    func handle(_ event: CPMMessagingHealthEvent) {
        switch event {
        case .navigationStarted(_, let navigationKind):
            events.append("started:\(navigationKind.rawValue)")
        case .navigationFailed:
            events.append("failed")
        case .navigationCommitted(_, let url):
            events.append("committed:\(url.absoluteString)")
        case .navigationFinished(_, let url, _):
            events.append("finished:\(url.absoluteString)")
        default:
            break
        }
    }
}

/// A web extension manager that only provides the health monitor, which is all a tab asks for.
@available(macOS 15.4, *)
private final class StubWebExtensionManager: WebExtensionManaging {

    let cpmMessagingHealthMonitor: CPMMessagingHealthMonitoring
    let eventsListener: WebExtensionEventsListening = WebExtensionEventsListener()
    let extensionsDirectory = FileManager.default.temporaryDirectory
    let loadedExtensions: Set<WKWebExtensionContext> = []
    let webExtensionIdentifiers: [String] = []
    let extensionUpdates = AsyncStream<Void>.makeStream().stream
    let lifecycleEvents = AsyncStream<WebExtensionLifecycleEvent>.makeStream().stream

    init(monitor: CPMMessagingHealthMonitoring) {
        self.cpmMessagingHealthMonitor = monitor
    }

    func attachExtensions(to configuration: WKWebViewConfiguration) {}
    func loadInstalledExtensions() async {}
    func reloadInstalledExtensions() async {}
    func installExtension(from sourceURL: URL) async throws {}
    func installExtension(from sourceURL: URL, storeIdentity: WebExtensionStoreIdentity?, replacing oldIdentifier: String?) async throws {}
    func uninstallExtension(identifier: String) throws {}
    func uninstallAllExtensions() -> [Result<Void, Error>] { [] }
    func syncEmbeddedExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async {}
    func uninstallEmbeddedExtension(type: DuckDuckGoWebExtensionType) {}
    func installedEmbeddedExtension(for type: DuckDuckGoWebExtensionType) -> InstalledWebExtension? { nil }
    func installedExtensionPath(for type: DuckDuckGoWebExtensionType) -> URL? { nil }
    func unloadAllExtensions() {}
    func reloadExtension(identifier: String) async throws {}
    func disableExtension(identifier: String) async throws {}
    func enableExtension(identifier: String) async throws {}
    func isRemotelyDisabled(identifier: String) -> Bool { false }
    func installedExtension(identifier: String) -> InstalledWebExtension? { nil }
    func extensionName(for identifier: String) -> String? { nil }
    func extensionVersion(for identifier: String) -> String? { nil }
    func extensionContext(for url: URL) -> WKWebExtensionContext? { nil }
    func context(for identifier: String) -> WKWebExtensionContext? { nil }
    func clearCachedScriptlets() {}
    func scriptletDebugInfo() -> [ScriptletDebugInfo] { [] }
}
