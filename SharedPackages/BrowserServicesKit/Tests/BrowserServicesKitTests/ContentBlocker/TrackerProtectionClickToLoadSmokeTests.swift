//
//  TrackerProtectionClickToLoadSmokeTests.swift
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

// Replacement Apple-side CTL smoke suite proving the new production path
// handles Click-to-Load *gating and reporting* semantics correctly:
//
//   WKWebView → WKContentRuleList (split: nonCTL + optional CTL)
//   → ContentScopeUserScript → TrackerProtectionSubfeature
//   → TrackerProtectionEventMapper (with split supplementary TDS)
//   → final DetectedRequest assertions
//
// SCOPE
// These tests focus on CTL-specific *transport* and *classification* behavior:
//   - CTL-active:   request blocked, classified as blocked in detectedTrackers
//   - CTL-inactive: request allowed, classified as non-blocked in
//                   detectedThirdPartyRequests with .ruleException
//   - non-CTL rule: still blocked regardless of CTL state
//
// Surrogate *injection* for CTL rules (fb-sdk.js) is NOT asserted here.
// When the CTL split-TDS setup compiles two WKContentRuleList instances,
// a pre-existing WebKit memory bug ("freed pointer was not the last
// allocation") can crash the process during surrogate execution. General
// bundled-surrogate injection is already covered by the separate
// TrackerProtectionBundledSurrogatesSmokeTests suite, which uses a single
// rule list and is not affected by this crash.
//
// This is NOT a literal migration of legacy ClickToLoadBlockingTests.swift.
// It uses the approved proxy-based harness with ClickToLoadRulesSplitter.
//
// Synthetic tracker domains (fb-tracker.org) are used to avoid HSTS/proxy
// interference from real public domains. The `.*` regex segments in the TDS
// fixture accommodate proxy-port-bearing test URLs.

#if os(macOS)

import BrowserServicesKit
import TrackerRadarKit
import WebKit
import XCTest

@available(macOS 14.0, iOS 17.0, *)
final class TrackerProtectionClickToLoadSmokeTests: XCTestCase {

    // MARK: - TDS Fixture

    // Synthetic tracker with both CTL and non-CTL rules. The `.*` between
    // domain and path accommodates proxy-port-bearing test URLs.
    // Rules reference real bundled surrogate names (fb-sdk.js).
    static let tdsJSON = """
    {
      "trackers": {
        "fb-tracker.org": {
          "domain": "fb-tracker.org",
          "owner": { "name": "FB Tracker Inc", "displayName": "FB Tracker" },
          "default": "ignore",
          "rules": [
            {
              "rule": "fb-tracker\\\\.org.*/sdk\\\\.js",
              "surrogate": "fb-sdk.js",
              "action": "block-ctl-fb"
            },
            {
              "rule": "fb-tracker\\\\.org.*/events\\\\.js"
            },
            {
              "rule": "fb-tracker\\\\.org",
              "action": "block-ctl-fb"
            }
          ]
        }
      },
      "entities": {
        "FB Tracker Inc": {
          "domains": ["fb-tracker.org"],
          "displayName": "FB Tracker",
          "prevalence": 0.5
        }
      },
      "domains": {
        "fb-tracker.org": "FB Tracker Inc"
      }
    }
    """

    // MARK: - Harness Factory

    /// Builds a test harness modeling the real CTL architecture:
    /// - C-S-S receives the full (merged) TDS so it can match CTL rules
    /// - native mapper receives split TDS via ClickToLoadRulesSplitter
    /// - content rules are compiled separately for nonCTL and CTL splits
    /// - CTL content rules and supplementary TDS are included only when ctlEnabled
    ///
    /// The config sets both `trackerProtection.settings.ctlEnabled` and
    /// `features.clickToLoad.state` for compatibility with the pre-built
    /// C-S-S bundle, which reads CTL state from the latter path.
    @MainActor
    private func makeHarness(ctlEnabled: Bool) async throws -> WebViewTestHarness {
        let fullTDS = try JSONDecoder().decode(TrackerData.self, from: Data(Self.tdsJSON.utf8))
        let dataSet = TrackerDataManager.DataSet(tds: fullTDS, etag: "test")
        let ruleList = ContentBlockerRulesList(
            name: "TrackerDataSet", trackerData: nil, fallbackTrackerData: dataSet)
        let splits = try XCTUnwrap(ClickToLoadRulesSplitter(rulesList: ruleList).split())

        let privacyConfig = WebViewTestConfig.preparePrivacyConfig()
        let configJSON = try WebViewTestConfig.makeConfig(ctlEnabled: ctlEnabled)
        let manager = WebViewTestConfig.makeManager(configJSON: configJSON, privacyConfig: privacyConfig)

        let supplementary: [TrackerData] = ctlEnabled
            ? [splits.withBlockCTL.fallbackTrackerData.tds]
            : []

        let proxy = TestLoopbackProxy()
        try await proxy.start()

        let harness = try WebViewTestHarness(
            trackerData: splits.withoutBlockCTL.fallbackTrackerData.tds,
            supplementaryTrackerData: supplementary,
            cssTrackerData: fullTDS,
            privacyConfigManager: manager,
            proxy: proxy)

        // Always install non-CTL content rules
        try await harness.compileAndInstallRules(
            trackerData: splits.withoutBlockCTL.fallbackTrackerData.tds,
            exceptions: [], tempUnprotected: [], trackerExceptions: [])

        // Install CTL content rules only when CTL is active
        if ctlEnabled {
            try await harness.compileAndInstallRules(
                trackerData: splits.withBlockCTL.fallbackTrackerData.tds,
                exceptions: [], tempUnprotected: [], trackerExceptions: [])
        }

        return harness
    }

    // MARK: - Test 1: CTL-active, catch-all rule → blocked

    @MainActor
    func testCTLActiveCatchAllRuleIsBlocked() async throws {
        let harness = try await makeHarness(ctlEnabled: true)
        defer { harness.proxy.stop() }

        let trackerHost = "fb-tracker.org"
        let trackerPath = "/some.js"
        let port = harness.proxy.port

        let pageHTML = """
        <html><body>
        <script>
        var s = document.createElement('script');
        s.src = 'http://\(trackerHost):\(port)\(trackerPath)';
        document.body.appendChild(s);
        </script>
        </body></html>
        """

        harness.registerContent(host: "page.example.com", path: "/index.html", body: pageHTML)
        harness.registerContent(host: trackerHost, path: trackerPath, body: "/* catch-all */")

        let trackerURL = "http://\(trackerHost):\(port)\(trackerPath)"
        let exp = harness.expectObservation(of: trackerURL, testCase: self)

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        XCTAssertFalse(
            harness.proxyDidReceive(host: trackerHost, path: trackerPath),
            "CTL catch-all request must be blocked by content rules")

        let blocked = harness.delegate.detectedTrackers.filter { $0.url == trackerURL }
        XCTAssertEqual(blocked.count, 1, "Exactly 1 blocked event expected")
        XCTAssertTrue(blocked.first?.isBlocked == true)

        let allowed = harness.delegate.detectedThirdPartyRequests.filter { $0.url == trackerURL }
        XCTAssertEqual(allowed.count, 0, "Zero non-blocked events expected")
    }

    // MARK: - Test 2: CTL-inactive, catch-all rule → allowed, non-blocked event

    @MainActor
    func testCTLInactiveCatchAllRuleIsAllowedAndReported() async throws {
        let harness = try await makeHarness(ctlEnabled: false)
        defer { harness.proxy.stop() }

        let trackerHost = "fb-tracker.org"
        let trackerPath = "/some.js"
        let port = harness.proxy.port

        let pageHTML = """
        <html><body>
        <script>
        var s = document.createElement('script');
        s.src = 'http://\(trackerHost):\(port)\(trackerPath)';
        document.body.appendChild(s);
        </script>
        </body></html>
        """

        harness.registerContent(host: "page.example.com", path: "/index.html", body: pageHTML)
        harness.registerContent(host: trackerHost, path: trackerPath, body: "/* allowed */")

        let trackerURL = "http://\(trackerHost):\(port)\(trackerPath)"
        let exp = harness.expectObservation(of: trackerURL, testCase: self)

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        XCTAssertTrue(
            harness.proxyDidReceive(host: trackerHost, path: trackerPath),
            "CTL-inactive request must reach proxy")

        let blocked = harness.delegate.detectedTrackers.filter { $0.url == trackerURL }
        XCTAssertEqual(blocked.count, 0, "Zero blocked events expected when CTL inactive")

        let allowed = harness.delegate.detectedThirdPartyRequests.filter { $0.url == trackerURL }
        XCTAssertEqual(allowed.count, 1, "Exactly 1 non-blocked event expected")
        XCTAssertFalse(allowed.first?.isBlocked == true)
        if case .allowed(reason: .ruleException) = allowed.first?.state {} else {
            XCTFail("Expected .ruleException for CTL-inactive ignore-default tracker, got \(String(describing: allowed.first?.state))")
        }

        XCTAssertEqual(harness.delegate.detectedSurrogates.count, 0,
                        "No surrogate events when CTL inactive")
    }

    // MARK: - Test 3: CTL-active, SDK/surrogate rule → blocked

    // This test verifies the CTL blocking/classification contract for an SDK
    // rule that also carries a surrogate declaration. Surrogate *injection* is
    // intentionally suppressed here via an integrity attribute on the script
    // element: with two compiled WKContentRuleList instances (nonCTL + CTL),
    // a pre-existing WebKit memory bug crashes the process when the fb-sdk.js
    // surrogate executes. The integrity attribute causes C-S-S to skip
    // surrogate loading while still classifying the request as blocked.
    // General bundled-surrogate injection is already proven by
    // TrackerProtectionBundledSurrogatesSmokeTests.

    @MainActor
    func testCTLActiveSDKRuleIsBlocked() async throws {
        let harness = try await makeHarness(ctlEnabled: true)
        defer { harness.proxy.stop() }

        let trackerHost = "fb-tracker.org"
        let trackerPath = "/sdk.js"
        let port = harness.proxy.port

        // integrity attribute prevents C-S-S from injecting the fb-sdk.js
        // surrogate, avoiding the WebKit crash while keeping the
        // transport/classification contract intact.
        let pageHTML = """
        <html><body>
        <script>
        var s = document.createElement('script');
        s.integrity = 'sha256-suppress-surrogate';
        s.src = 'http://\(trackerHost):\(port)\(trackerPath)';
        document.body.appendChild(s);
        </script>
        </body></html>
        """

        harness.registerContent(host: "page.example.com", path: "/index.html", body: pageHTML)
        harness.registerContent(host: trackerHost, path: trackerPath, body: "/* blocked SDK */")

        let trackerURL = "http://\(trackerHost):\(port)\(trackerPath)"
        let exp = harness.expectObservation(of: trackerURL, testCase: self)

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        XCTAssertFalse(
            harness.proxyDidReceive(host: trackerHost, path: trackerPath),
            "CTL SDK request must be blocked by content rules")

        let blocked = harness.delegate.detectedTrackers.filter { $0.url == trackerURL }
        XCTAssertEqual(blocked.count, 1, "Exactly 1 blocked event expected for SDK")
        XCTAssertTrue(blocked.first?.isBlocked == true)

        let allowed = harness.delegate.detectedThirdPartyRequests.filter { $0.url == trackerURL }
        XCTAssertEqual(allowed.count, 0, "Zero non-blocked events expected for SDK")
    }

    // MARK: - Test 4: CTL-inactive, SDK/surrogate rule → allowed, no surrogate

    @MainActor
    func testCTLInactiveSDKRuleIsAllowedNoSurrogate() async throws {
        let harness = try await makeHarness(ctlEnabled: false)
        defer { harness.proxy.stop() }

        let trackerHost = "fb-tracker.org"
        let trackerPath = "/sdk.js"
        let port = harness.proxy.port

        let pageHTML = """
        <html><body>
        <script>
        var s = document.createElement('script');
        s.src = 'http://\(trackerHost):\(port)\(trackerPath)';
        document.body.appendChild(s);
        </script>
        </body></html>
        """

        harness.registerContent(host: "page.example.com", path: "/index.html", body: pageHTML)
        harness.registerContent(host: trackerHost, path: trackerPath, body: "window.__sdkLoaded = true;")

        let trackerURL = "http://\(trackerHost):\(port)\(trackerPath)"
        let exp = harness.expectObservation(of: trackerURL, testCase: self)

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        XCTAssertTrue(
            harness.proxyDidReceive(host: trackerHost, path: trackerPath),
            "CTL-inactive SDK request must reach proxy")

        let blocked = harness.delegate.detectedTrackers.filter { $0.url == trackerURL }
        XCTAssertEqual(blocked.count, 0, "Zero blocked events when CTL inactive")

        let allowed = harness.delegate.detectedThirdPartyRequests.filter { $0.url == trackerURL }
        XCTAssertEqual(allowed.count, 1, "Exactly 1 non-blocked event expected")
        XCTAssertFalse(allowed.first?.isBlocked == true)
        if case .allowed(reason: .ruleException) = allowed.first?.state {} else {
            XCTFail("Expected .ruleException for CTL-inactive SDK, got \(String(describing: allowed.first?.state))")
        }

        XCTAssertEqual(harness.delegate.detectedSurrogates.count, 0,
                        "No surrogate when CTL inactive")

        // The real SDK script loaded, not the surrogate
        let sdkLoaded = try await harness.evaluateJS(
            "window.__sdkLoaded === true") as? Bool
        XCTAssertEqual(sdkLoaded, true, "Actual SDK script should have loaded")

        // Surrogate-specific global should NOT exist
        let fbDefined = try await harness.evaluateJS(
            "typeof window.FB !== 'undefined'") as? Bool
        XCTAssertNotEqual(fbDefined, true, "Surrogate window.FB should NOT exist")
    }

    // MARK: - Test 5: Non-CTL control rule, CTL inactive → still blocked

    @MainActor
    func testNonCTLRuleStillBlockedWhenCTLInactive() async throws {
        let harness = try await makeHarness(ctlEnabled: false)
        defer { harness.proxy.stop() }

        let trackerHost = "fb-tracker.org"
        let trackerPath = "/events.js"
        let port = harness.proxy.port

        let pageHTML = """
        <html><body>
        <script>
        var s = document.createElement('script');
        s.src = 'http://\(trackerHost):\(port)\(trackerPath)';
        document.body.appendChild(s);
        </script>
        </body></html>
        """

        harness.registerContent(host: "page.example.com", path: "/index.html", body: pageHTML)
        harness.registerContent(host: trackerHost, path: trackerPath, body: "/* events */")

        let trackerURL = "http://\(trackerHost):\(port)\(trackerPath)"
        let exp = harness.expectObservation(of: trackerURL, testCase: self)

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        XCTAssertFalse(
            harness.proxyDidReceive(host: trackerHost, path: trackerPath),
            "Non-CTL rule must still be blocked regardless of CTL state")

        let blocked = harness.delegate.detectedTrackers.filter { $0.url == trackerURL }
        XCTAssertEqual(blocked.count, 1, "Exactly 1 blocked event expected for non-CTL rule")
        XCTAssertTrue(blocked.first?.isBlocked == true)

        let allowed = harness.delegate.detectedThirdPartyRequests.filter { $0.url == trackerURL }
        XCTAssertEqual(allowed.count, 0, "Zero non-blocked events for non-CTL blocked rule")
    }
}

#endif
