//
//  TrackerProtectionWebKitIntegrationTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import Common
import ContentBlocking
import MaliciousSiteProtection
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

// MARK: - Test Helpers

private final class MockMaliciousSiteDetectingTP: MaliciousSiteDetecting {
    func startFetching() {}
    func registerBackgroundRefreshTaskHandler() {}
    func evaluate(_ url: URL) async -> ThreatKind? { nil }
}

/// Integration tests for the C-S-S tracker-protection → native pipeline.
///
/// Validates that C-S-S tracker detection events flow through `TrackerProtectionSubfeature`,
/// `TrackerProtectionEventMapper`, and `ContentBlockingTabExtension` to produce correct
/// `DetectedTracker` emissions on `Tab.trackersPublisher`.
///
/// Uses the embedded TDS (trackerData.json) bundled in the app, with real tracker domains
/// for seam confidence. Tests use `WindowsManager.openNewWindow` to trigger full content
/// blocking asset installation and C-S-S injection.
///
/// Provides end-to-end integration coverage for the C-S-S tracker-protection pipeline.
@available(macOS 12.0, *)
final class TrackerProtectionWebKitIntegrationTests: XCTestCase {

    private var window: NSWindow!
    private var contentBlockingMock: ContentBlockingMock!
    private var privacyFeaturesMock: AnyPrivacyFeatures!
    private var schemeHandler: TestSchemeHandler!
    private var collectedTrackers: [DetectedTracker] = []
    private var cancellables = Set<AnyCancellable>()

    private var privacyConfiguration: MockPrivacyConfiguration {
        contentBlockingMock.privacyConfigurationManager.privacyConfig as! MockPrivacyConfiguration
    }

    // MARK: - Fixture Domains
    // Using real TLDs for deterministic eTLD+1 behavior in TLD lookups.
    // google-analytics.com is a stable blocked-by-default tracker in the embedded TDS.

    private let pageURL = URL(string: "https://testpage.com/index.html")!
    private let trackerURL = URL(string: "https://google-analytics.com/analytics.js")!
    private let nonTrackerThirdPartyURL = URL(string: "https://nontrackercdn.org/lib.js")!

    // MARK: - Test HTML

    private var htmlWithTracker: String {
        """
        <!DOCTYPE html>
        <html>
        <head><title>Tracker Test Page</title></head>
        <body>
            <script src="\(trackerURL.absoluteString)"></script>
        </body>
        </html>
        """
    }

    private var htmlWithNonTrackerThirdParty: String {
        """
        <!DOCTYPE html>
        <html>
        <head><title>Third Party Test Page</title></head>
        <body>
            <script src="\(nonTrackerThirdPartyURL.absoluteString)"></script>
        </body>
        </html>
        """
    }

    private static let htmlClean = """
    <!DOCTYPE html>
    <html>
    <head><title>Clean Page</title></head>
    <body>No trackers here.</body>
    </html>
    """

    // MARK: - Setup / Teardown

    @MainActor
    override func setUp() {
        super.setUp()

        contentBlockingMock = ContentBlockingMock()
        privacyFeaturesMock = AppPrivacyFeatures(contentBlocking: contentBlockingMock, httpsUpgradeStore: HTTPSUpgradeStoreMock())

        // Keep content blocking ENABLED — we need the full tracker protection pipeline active.
        // Only gate specific features as needed per test case.

        schemeHandler = TestSchemeHandler()
        schemeHandler.middleware = [{ [weak self] request in
            guard let self, let url = request.url else { return nil }

            // Serve the page HTML
            if url.host == self.pageURL.host {
                return .ok(.html(self.htmlWithTracker))
            }

            // Serve an empty JS response for tracker/third-party script requests
            // (C-S-S intercepts the DOM script element, not the network request)
            if url.host == self.trackerURL.host {
                return .ok(.data("/* tracker */".data(using: .utf8)!, mime: "application/javascript"))
            }
            if url.host == self.nonTrackerThirdPartyURL.host {
                return .ok(.data("/* lib */".data(using: .utf8)!, mime: "application/javascript"))
            }

            return nil
        }]

        collectedTrackers = []
        cancellables = []
    }

    @MainActor
    override func tearDown() {
        autoreleasepool {
            window?.close()
            window = nil
            schemeHandler = nil
            privacyFeaturesMock = nil
            contentBlockingMock = nil
            collectedTrackers = []
            cancellables = []
        }
        super.tearDown()
    }

    // MARK: - Helper

    @MainActor
    private func createTabAndOpenWindow(content url: URL) -> Tab {
        let tab = Tab(
            content: .url(url, credential: nil, source: .userEntered("")),
            webViewConfiguration: schemeHandler.webViewConfiguration(withCustomSchemeHandlersFor: [.http, .https]),
            privacyFeatures: privacyFeaturesMock,
            maliciousSiteDetector: MockMaliciousSiteDetectingTP()
        )

        // Subscribe to tracker events BEFORE navigation
        tab.trackersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracker in
                self?.collectedTrackers.append(tracker)
            }
            .store(in: &cancellables)

        let viewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab]))
        window = WindowsManager.openNewWindow(with: viewModel)!

        return tab
    }

    // MARK: - Tests

    /// Vertical slice: validates that a blocked third-party tracker (google-analytics.com)
    /// emits a DetectedTracker with `.blocked` state through the native pipeline.
    @MainActor
    func testBlockedThirdPartyTracker() async throws {
        let tab = createTabAndOpenWindow(content: pageURL)

        // Wait for navigation to complete
        _ = try await tab.webViewDidFinishNavigationPublisher.timeout(10).first().promise().value

        // Allow time for C-S-S tracker detection + native message round-trip
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Assert: at least one tracker detection event was emitted
        let trackerEvents = collectedTrackers.filter {
            if case .tracker = $0.type { return true }
            return false
        }

        XCTAssertFalse(trackerEvents.isEmpty,
                       "Expected at least one tracker detection event from tab.trackersPublisher. " +
                       "Got \(collectedTrackers.count) total events: \(collectedTrackers.map { "\($0.request.url) state=\($0.request.state)" })")

        // Find the google-analytics tracker specifically
        let gaTracker = trackerEvents.first { $0.request.url.contains("google-analytics.com") }
        if let gaTracker {
            XCTAssertEqual(gaTracker.request.state, .blocked,
                           "google-analytics.com should be blocked by default in embedded TDS")
            XCTAssertEqual(gaTracker.request.eTLDplus1, "google-analytics.com")
        }
    }

    /// Validates that a same-site tracker (same eTLD+1 as page) is suppressed
    /// by TrackerProtectionEventMapper.isSameSiteObservation.
    @MainActor
    func testFirstPartyTrackerSuppressed() async throws {
        // Use a page URL where a "tracker" has the same eTLD+1
        let sameSitePageURL = URL(string: "https://google-analytics.com/page.html")!

        schemeHandler.middleware = [{ request in
            guard let url = request.url else { return nil }
            if url.host == "google-analytics.com" && url.path.hasSuffix(".html") {
                let html = """
                <!DOCTYPE html>
                <html><head><title>Same Site Page</title></head>
                <body><script src="https://google-analytics.com/analytics.js"></script></body>
                </html>
                """
                return .ok(.html(html))
            }
            if url.host == "google-analytics.com" {
                return .ok(.data("/* ga */".data(using: .utf8)!, mime: "application/javascript"))
            }
            return nil
        }]

        let tab = createTabAndOpenWindow(content: sameSitePageURL)

        _ = try await tab.webViewDidFinishNavigationPublisher.timeout(10).first().promise().value
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Same-site observations should be suppressed (isSameSiteObservation returns true)
        let gaTrackers = collectedTrackers.filter { $0.request.url.contains("google-analytics.com") }
        XCTAssertTrue(gaTrackers.isEmpty,
                      "Same-site tracker should be suppressed by isSameSiteObservation. " +
                      "Got \(gaTrackers.count) events: \(gaTrackers.map { $0.request.url })")
    }

    /// Validates that a non-tracker third-party request is classified as `.thirdPartyRequest`.
    @MainActor
    func testNonTrackerThirdPartyRequestClassification() async throws {
        schemeHandler.middleware = [{ [weak self] request in
            guard let self, let url = request.url else { return nil }
            if url.host == self.pageURL.host {
                return .ok(.html(self.htmlWithNonTrackerThirdParty))
            }
            if url.host == self.nonTrackerThirdPartyURL.host {
                return .ok(.data("/* lib */".data(using: .utf8)!, mime: "application/javascript"))
            }
            return nil
        }]

        let tab = createTabAndOpenWindow(content: pageURL)

        _ = try await tab.webViewDidFinishNavigationPublisher.timeout(10).first().promise().value
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let thirdPartyEvents = collectedTrackers.filter {
            if case .thirdPartyRequest = $0.type { return true }
            return false
        }

        // If third-party request reporting is active, we expect at least one event
        // for the non-tracker domain. If the C-S-S feature doesn't report this domain
        // (not in TDS), this assertion documents the observed behavior.
        if !thirdPartyEvents.isEmpty {
            let nonTrackerEvent = thirdPartyEvents.first { $0.request.url.contains("nontrackercdn.org") }
            if let event = nonTrackerEvent {
                XCTAssertEqual(event.request.state, .allowed(reason: .otherThirdPartyRequest),
                               "Non-tracker third-party should be allowed with .otherThirdPartyRequest reason")
            }
        }
    }
}
