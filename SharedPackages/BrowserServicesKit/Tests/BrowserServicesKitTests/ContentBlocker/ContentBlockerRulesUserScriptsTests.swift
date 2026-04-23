//
//  ContentBlockerRulesUserScriptsTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

// Tests are disabled on iOS due to WKWebView stability issues on the iOS 17.5+ simulator.
#if os(macOS)

import BrowserServicesKit
import Common
import ContentBlocking
import PrivacyConfig
import TrackerRadarKit
import WebKit
import XCTest

/// Tests the full ContentScopeUserScript → TrackerProtectionSubfeature →
/// TrackerProtectionEventMapper pipeline using the proxy-based WebView harness.
///
/// Migrated from the legacy ContentBlockerRulesUserScript + test:// scheme
/// tests. Each test preserves the old behavioral contract expressed through
/// the new production path.
///
/// Tests 9 and 12 depend on the temp-list subdomain override in
/// TrackerProtectionEventMapper (TrackerResolver.isPageOnUnprotectedSitesOrTempList
/// uses exact string matching; the mapper adds subdomain coverage for tempList
/// entries, matching the old content-rule `if-domain` behavior).
@available(macOS 14.0, iOS 17.0, *)
class ContentBlockerRulesUserScriptsTests: XCTestCase {

    static let tdsJSON = """
    {
      "trackers": {
        "tracker.com": {
          "domain": "tracker.com",
          "default": "block",
          "owner": {
            "name": "Fake Tracking Inc",
            "displayName": "FT Inc",
            "privacyPolicy": "https://tracker.com/privacy",
            "url": "http://tracker.com"
          },
          "source": ["DDG"],
          "prevalence": 0.002,
          "fingerprinting": 0,
          "cookies": 0.002,
          "performance": { "time": 1, "size": 1, "cpu": 1, "cache": 3 },
          "categories": [
            "Ad Motivated Tracking",
            "Advertising",
            "Analytics",
            "Third-Party Analytics Marketing"
          ]
        }
      },
      "entities": {
        "Fake Tracking Inc": {
          "domains": ["tracker.com", "trackeraffiliated.com"],
          "displayName": "Fake Tracking Inc",
          "prevalence": 0.1
        }
      },
      "domains": {
        "tracker.com": "Fake Tracking Inc",
        "trackeraffiliated.com": "Fake Tracking Inc"
      },
      "cnames": {}
    }
    """

    private let resourceHosts = [
        "nontracker.com", "tracker.com", "sub.tracker.com", "trackeraffiliated.com"
    ]

    // MARK: - Helpers

    private func makePageHTML(port: UInt16) -> String {
        """
        <html><body>
        <script>
        ['nontracker.com', 'tracker.com', 'sub.tracker.com', 'trackeraffiliated.com'].forEach(function(host) {
            var img = document.createElement('img');
            img.src = 'http://' + host + ':\(port)/1.png';
            document.body.appendChild(img);
        });
        </script>
        </body></html>
        """
    }

    @MainActor
    private func registerStandardResources(on harness: WebViewTestHarness) {
        for host in resourceHosts {
            harness.registerContent(host: host, path: "/1.png", body: "IMGDATA")
        }
    }

    @MainActor
    private func loadPageAndWaitForObservations(
        harness: WebViewTestHarness,
        pageHost: String
    ) async throws {
        harness.registerContent(
            host: pageHost, path: "/index.html",
            body: makePageHTML(port: harness.proxy.port))
        registerStandardResources(on: harness)

        let expectations = resourceHosts.map { host in
            harness.expectObservation(
                of: "http://\(host):\(harness.proxy.port)/1.png",
                testCase: self)
        }

        try await harness.load(host: pageHost)
        await fulfillment(of: expectations, timeout: 10)
    }

    // MARK: - Test 1: Normal third-party tracker blocking

    @MainActor
    func testWhenThereIsTrackerThenItIsReportedAndBlocked() async throws {
        let harness = try await WebViewTestHarness.create(trackerDataJSON: Self.tdsJSON)
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "example.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertEqual(blockedDomains, ["tracker.com", "sub.tracker.com"])

        let thirdPartyDomains = Set(harness.delegate.detectedThirdPartyRequests.map { $0.domain })
        XCTAssertEqual(thirdPartyDomains, ["nontracker.com", "trackeraffiliated.com"])

        XCTAssertTrue(harness.proxyDidReceive(host: "nontracker.com", path: "/1.png"))
        XCTAssertTrue(harness.proxyDidReceive(host: "trackeraffiliated.com", path: "/1.png"))
        XCTAssertFalse(harness.proxyDidReceive(host: "tracker.com", path: "/1.png"))
        XCTAssertFalse(harness.proxyDidReceive(host: "sub.tracker.com", path: "/1.png"))
    }

    // MARK: - Test 2: First-party tracker (page = tracker.com)

    @MainActor
    func testWhenThereIsFirstPartyTrackerThenItIsNotBlocked() async throws {
        let harness = try await WebViewTestHarness.create(trackerDataJSON: Self.tdsJSON)
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "tracker.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertTrue(blockedDomains.isEmpty)

        let detectedTrackerDomains = Set(harness.delegate.detectedTrackers.map { $0.domain })
        XCTAssertTrue(detectedTrackerDomains.isEmpty)

        let thirdPartyDomains = Set(harness.delegate.detectedThirdPartyRequests.map { $0.domain })
        XCTAssertEqual(thirdPartyDomains, ["nontracker.com", "trackeraffiliated.com"])

        let ownedByFirstParty = Set(
            harness.delegate.detectedThirdPartyRequests
                .filter { $0.state == .allowed(reason: .ownedByFirstParty) }
                .compactMap { $0.domain })
        XCTAssertEqual(ownedByFirstParty, ["trackeraffiliated.com"])

        let otherThirdParty = Set(
            harness.delegate.detectedThirdPartyRequests
                .filter { $0.state == .allowed(reason: .otherThirdPartyRequest) }
                .compactMap { $0.domain })
        XCTAssertEqual(otherThirdParty, ["nontracker.com"])

        for host in resourceHosts {
            XCTAssertTrue(harness.proxyDidReceive(host: host, path: "/1.png"),
                          "\(host) must reach proxy when page is first-party")
        }
    }

    // MARK: - Test 3: First-party non-tracker page (page = nontracker.com)

    @MainActor
    func testWhenThereIsFirstPartyRequestThenItIsNotBlocked() async throws {
        let harness = try await WebViewTestHarness.create(trackerDataJSON: Self.tdsJSON)
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "nontracker.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertEqual(blockedDomains, ["tracker.com", "sub.tracker.com"])

        let thirdPartyDomains = Set(harness.delegate.detectedThirdPartyRequests.map { $0.domain })
        XCTAssertEqual(thirdPartyDomains, ["trackeraffiliated.com"])

        XCTAssertTrue(harness.proxyDidReceive(host: "nontracker.com", path: "/1.png"))
        XCTAssertTrue(harness.proxyDidReceive(host: "trackeraffiliated.com", path: "/1.png"))
        XCTAssertFalse(harness.proxyDidReceive(host: "tracker.com", path: "/1.png"))
        XCTAssertFalse(harness.proxyDidReceive(host: "sub.tracker.com", path: "/1.png"))
    }

    // MARK: - Test 4: Locally unprotected site (exact host)

    @MainActor
    func testWhenThereIsTrackerOnLocallyUnprotectedSiteThenItIsReportedButNotBlocked() async throws {
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: Self.tdsJSON,
            locallyUnprotected: ["example.com"])
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "example.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertTrue(blockedDomains.isEmpty)

        let trackerDomains = Set(
            harness.delegate.detectedThirdPartyRequests
                .filter { $0.state == .allowed(reason: .protectionDisabled) }
                .compactMap { $0.domain })
        XCTAssertEqual(trackerDomains, ["tracker.com", "sub.tracker.com"])

        for host in resourceHosts {
            XCTAssertTrue(harness.proxyDidReceive(host: host, path: "/1.png"),
                          "\(host) must reach proxy on locally unprotected site")
        }
    }

    // MARK: - Test 5: Tracker allowlist

    @MainActor
    func testWhenThereIsTrackerOnAllowlistThenItIsReportedButNotBlocked() async throws {
        let allowlist: [String: [PrivacyConfigurationData.TrackerAllowlist.Entry]] = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker.com/", domains: ["<all>"])
            ]
        ]
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: Self.tdsJSON,
            trackerAllowlist: allowlist)
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "example.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertTrue(blockedDomains.isEmpty)

        let allowedTrackerDomains = Set(
            harness.delegate.detectedThirdPartyRequests
                .filter { !$0.isBlocked }
                .filter { $0.domain == "tracker.com" || $0.domain == "sub.tracker.com" }
                .compactMap { $0.domain })
        XCTAssertEqual(allowedTrackerDomains, ["tracker.com", "sub.tracker.com"])

        for host in resourceHosts {
            XCTAssertTrue(harness.proxyDidReceive(host: host, path: "/1.png"),
                          "\(host) must reach proxy when tracker is allowlisted")
        }
    }

    // MARK: - Test 6: Locally unprotected subdomain (exact-host only — still blocked)

    @MainActor
    func testWhenThereIsTrackerOnLocallyUnprotectedSiteSubdomainThenItIsReportedAndBlocked() async throws {
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: Self.tdsJSON,
            locallyUnprotected: ["example.com"])
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "sub.example.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertEqual(blockedDomains, ["tracker.com", "sub.tracker.com"])

        XCTAssertFalse(harness.proxyDidReceive(host: "tracker.com", path: "/1.png"))
        XCTAssertFalse(harness.proxyDidReceive(host: "sub.tracker.com", path: "/1.png"))
        XCTAssertTrue(harness.proxyDidReceive(host: "nontracker.com", path: "/1.png"))
        XCTAssertTrue(harness.proxyDidReceive(host: "trackeraffiliated.com", path: "/1.png"))
    }

    // MARK: - Test 7: Similar domain to locally unprotected (still blocked)

    @MainActor
    func testWhenThereIsTrackerOnSiteSimmilarToLocallyUnprotectedSiteThenItIsReportedAndBlocked() async throws {
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: Self.tdsJSON,
            locallyUnprotected: ["example.com"])
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "someexample.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertEqual(blockedDomains, ["tracker.com", "sub.tracker.com"])

        XCTAssertFalse(harness.proxyDidReceive(host: "tracker.com", path: "/1.png"))
        XCTAssertFalse(harness.proxyDidReceive(host: "sub.tracker.com", path: "/1.png"))
        XCTAssertTrue(harness.proxyDidReceive(host: "nontracker.com", path: "/1.png"))
        XCTAssertTrue(harness.proxyDidReceive(host: "trackeraffiliated.com", path: "/1.png"))
    }

    // MARK: - Test 8: Temp-unprotected site (exact host)

    @MainActor
    func testWhenThereIsTrackerOnTempUnprotectedSiteThenItIsReportedButNotBlocked() async throws {
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: Self.tdsJSON,
            tempUnprotected: ["example.com"])
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "example.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertTrue(blockedDomains.isEmpty)

        let trackerDomains = Set(
            harness.delegate.detectedThirdPartyRequests
                .filter { $0.state == .allowed(reason: .protectionDisabled) }
                .compactMap { $0.domain })
        XCTAssertEqual(trackerDomains, ["tracker.com", "sub.tracker.com"])

        for host in resourceHosts {
            XCTAssertTrue(harness.proxyDidReceive(host: host, path: "/1.png"),
                          "\(host) must reach proxy on temp-unprotected site")
        }
    }

    // MARK: - Test 9: Temp-unprotected subdomain (covers subdomains)

    @MainActor
    func testWhenThereIsTrackerOnTempUnprotectedSiteSubdomainThenItIsReportedButNotBlocked() async throws {
        // Subdomain coverage is provided by TrackerProtectionEventMapper's
        // applyTempListSubdomainOverride — TrackerResolver uses exact matching.
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: Self.tdsJSON,
            tempUnprotected: ["example.com"])
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "sub.example.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertTrue(blockedDomains.isEmpty)

        let trackerDomains = Set(
            harness.delegate.detectedThirdPartyRequests
                .filter { $0.state == .allowed(reason: .protectionDisabled) }
                .compactMap { $0.domain })
        XCTAssertEqual(trackerDomains, ["tracker.com", "sub.tracker.com"])

        for host in resourceHosts {
            XCTAssertTrue(harness.proxyDidReceive(host: host, path: "/1.png"),
                          "\(host) must reach proxy on temp-unprotected subdomain")
        }
    }

    // MARK: - Test 10: Similar domain to temp-unprotected (still blocked)

    @MainActor
    func testWhenThereIsTrackerOnSiteSimmilarToTempUnprotectedSiteThenItIsReportedAndBlocked() async throws {
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: Self.tdsJSON,
            tempUnprotected: ["example.com"])
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "someexample.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertEqual(blockedDomains, ["tracker.com", "sub.tracker.com"])

        XCTAssertFalse(harness.proxyDidReceive(host: "tracker.com", path: "/1.png"))
        XCTAssertFalse(harness.proxyDidReceive(host: "sub.tracker.com", path: "/1.png"))
        XCTAssertTrue(harness.proxyDidReceive(host: "nontracker.com", path: "/1.png"))
        XCTAssertTrue(harness.proxyDidReceive(host: "trackeraffiliated.com", path: "/1.png"))
    }

    // MARK: - Test 11: Exception-list site (exact host)

    @MainActor
    func testWhenThereIsTrackerOnSiteFromExceptionListThenItIsReportedButNotBlocked() async throws {
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: Self.tdsJSON,
            exceptions: ["example.com"])
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "example.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertTrue(blockedDomains.isEmpty)

        let trackerDomains = Set(
            harness.delegate.detectedThirdPartyRequests
                .filter { $0.state == .allowed(reason: .protectionDisabled) }
                .compactMap { $0.domain })
        XCTAssertEqual(trackerDomains, ["tracker.com", "sub.tracker.com"])

        for host in resourceHosts {
            XCTAssertTrue(harness.proxyDidReceive(host: host, path: "/1.png"),
                          "\(host) must reach proxy on exception-list site")
        }
    }

    // MARK: - Test 12: Exception-list subdomain (covers subdomains)

    @MainActor
    func testWhenThereIsTrackerOnSubdomainOfSiteFromExceptionListThenItIsReportedButNotBlocked() async throws {
        // Subdomain coverage is provided by TrackerProtectionEventMapper's
        // applyTempListSubdomainOverride — exception-list domains are merged
        // into tempList.
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: Self.tdsJSON,
            exceptions: ["example.com"])
        defer { harness.proxy.stop() }

        try await loadPageAndWaitForObservations(harness: harness, pageHost: "sub.example.com")

        let blockedDomains = Set(harness.delegate.detectedTrackers.filter { $0.isBlocked }.map { $0.domain })
        XCTAssertTrue(blockedDomains.isEmpty)

        let trackerDomains = Set(
            harness.delegate.detectedThirdPartyRequests
                .filter { $0.state == .allowed(reason: .protectionDisabled) }
                .compactMap { $0.domain })
        XCTAssertEqual(trackerDomains, ["tracker.com", "sub.tracker.com"])

        for host in resourceHosts {
            XCTAssertTrue(harness.proxyDidReceive(host: host, path: "/1.png"),
                          "\(host) must reach proxy on exception-list subdomain")
        }
    }

    // MARK: - Test 13: Content blocking disabled (DEFERRED)

    @MainActor
    func testWhenContentBlockingFeatureIsDisabledThenTrackersAreReportedButNotBlocked() async throws {
        throw XCTSkip(
            """
            DEFERRED: C-S-S stops observing resources entirely when \
            blockingEnabled == false (remote-config kill-switch), while the \
            old pipeline continued observing and classifying trackers as \
            non-blocked. Restoring this behavior requires a C-S-S change, \
            not a native fix. This is distinct from per-site protections-off \
            (userUnprotectedDomains), which is already tested above.
            """)
    }
}

#endif
