//
//  TrackerProtectionBundledSurrogatesSmokeTests.swift
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

// Apple-side smoke tests proving real bundled surrogates work end-to-end
// through the new production path:
//
//   WKWebView → WKContentRuleList → ContentScopeUserScript →
//   TrackerProtectionSubfeature → native surrogate event → page-side JS effect
//
// This is NOT a migration of legacy SurrogatesReferenceTests or
// SurrogatesUserScriptTests. Those remain deferred because they depend on
// custom test surrogates not present in the bundled surrogates-generated.js.
//
// Surrogate names and expected page-side effects are sourced from the C-S-S
// integration test suite (tracker-protection.spec.js / tracker-data-fixtures.js).

#if os(macOS)

import BrowserServicesKit
import TrackerRadarKit
import WebKit
import XCTest

@available(macOS 14.0, iOS 17.0, *)
final class TrackerProtectionBundledSurrogatesSmokeTests: XCTestCase {

    /// Evaluate JavaScript in the web view, disambiguating the WebKit vs Common overload.
    @MainActor
    private func evaluateJS(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: result)
                }
            }
        }
    }

    // Synthetic TDS referencing real bundled surrogate names.
    // Surrogate names sourced from makeTrackerDataGoogle() in C-S-S integration fixtures.
    //
    // Uses proxy-safe tracker domains (not HSTS-preloaded) so the unprotected
    // negative test can observe the request reaching the proxy over plain HTTP.
    // The surrogate names are what matter — they must match bundled surrogates.
    private static let tdsJSON = """
    {
      "trackers": {
        "analytics-tracker.org": {
          "domain": "analytics-tracker.org",
          "default": "block",
          "owner": { "name": "Analytics Corp", "displayName": "Analytics Corp" },
          "rules": [
            { "rule": "analytics-tracker\\\\.org.*/analytics\\\\.js", "surrogate": "analytics.js" }
          ]
        },
        "adservices-tracker.org": {
          "domain": "adservices-tracker.org",
          "default": "block",
          "owner": { "name": "Ads Corp", "displayName": "Ads Corp" },
          "rules": [
            { "rule": "adservices-tracker\\\\.org.*/tag/js/gpt\\\\.js", "surrogate": "gpt.js" }
          ]
        }
      },
      "entities": {
        "Analytics Corp": {
          "domains": ["analytics-tracker.org"],
          "displayName": "Analytics Corp",
          "prevalence": 0.5
        },
        "Ads Corp": {
          "domains": ["adservices-tracker.org"],
          "displayName": "Ads Corp",
          "prevalence": 0.5
        }
      },
      "domains": {
        "analytics-tracker.org": "Analytics Corp",
        "adservices-tracker.org": "Ads Corp"
      },
      "cnames": {}
    }
    """

    // MARK: - Test 1: Bundled surrogate injects and executes

    @MainActor
    func testBundledSurrogateInjectsAndExecutes() async throws {
        let harness = try await WebViewTestHarness.create(trackerDataJSON: Self.tdsJSON)
        defer { harness.proxy.stop() }

        let trackerHost = "analytics-tracker.org"
        let trackerPath = "/analytics.js"
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
        harness.registerContent(host: trackerHost, path: trackerPath, body: "/* blocked */")

        let trackerURL = "http://\(trackerHost):\(port)\(trackerPath)"
        let exp = harness.expectObservation(of: trackerURL, testCase: self)
        // Both resourceObserved and surrogateInjected fire for this URL.
        exp.expectedFulfillmentCount = 2

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        // Layer 1: content rules blocked the tracker — proxy never received it
        XCTAssertFalse(
            harness.proxyDidReceive(host: trackerHost, path: trackerPath),
            "Content rules should block the tracker request")

        // Layer 2: native surrogate event was captured
        XCTAssertEqual(
            harness.delegate.detectedSurrogates.count, 1,
            "Exactly one surrogate injection expected")
        if let (detected, host) = harness.delegate.detectedSurrogates.first {
            XCTAssertTrue(detected.isBlocked, "Surrogate replaces a blocked tracker")
            XCTAssertEqual(host, trackerHost)
        }

        // Layer 3: bundled surrogate JS actually executed — analytics.js defines window.ga
        let gaIsDefined = try await evaluateJS(
            "typeof window.ga === 'function'", in: harness.webView) as? Bool
        XCTAssertEqual(gaIsDefined, true, "analytics.js surrogate should define window.ga")
    }

    // MARK: - Test 2: Integrity attribute prevents surrogate injection

    @MainActor
    func testIntegrityAttributePreventsSurrogateInjection() async throws {
        let harness = try await WebViewTestHarness.create(trackerDataJSON: Self.tdsJSON)
        defer { harness.proxy.stop() }

        let trackerHost = "analytics-tracker.org"
        let trackerPath = "/analytics.js"
        let port = harness.proxy.port

        let pageHTML = """
        <html><body>
        <script>
        var s = document.createElement('script');
        s.integrity = 'sha512-fakehash';
        s.crossOrigin = 'anonymous';
        s.src = 'http://\(trackerHost):\(port)\(trackerPath)';
        document.body.appendChild(s);
        </script>
        </body></html>
        """

        harness.registerContent(host: "page.example.com", path: "/index.html", body: pageHTML)
        harness.registerContent(host: trackerHost, path: trackerPath, body: "/* blocked */")

        let trackerURL = "http://\(trackerHost):\(port)\(trackerPath)"
        // Only resourceObserved fires (no surrogateInjected due to integrity).
        let exp = harness.expectObservation(of: trackerURL, testCase: self)

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        // Content rules still block the tracker
        XCTAssertFalse(
            harness.proxyDidReceive(host: trackerHost, path: trackerPath),
            "Content rules should block the tracker request")

        // No surrogate injection due to integrity attribute
        XCTAssertEqual(
            harness.delegate.detectedSurrogates.count, 0,
            "Integrity attribute should prevent surrogate injection")

        // Page should NOT have the surrogate's global
        let gaIsDefined = try await evaluateJS(
            "typeof window.ga === 'function'", in: harness.webView) as? Bool
        XCTAssertNotEqual(gaIsDefined, true, "No surrogate should have executed")
    }

    // MARK: - Test 3: Exception-listed domain — no blocking, no surrogate

    @MainActor
    func testExceptionListedDomainPreventsBlocking() async throws {
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: Self.tdsJSON,
            exceptions: ["page.example.com"])
        defer { harness.proxy.stop() }

        let trackerHost = "analytics-tracker.org"
        let trackerPath = "/pixel.js"
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
        harness.registerContent(host: trackerHost, path: trackerPath,
                                body: "window.__trackerLoaded = true;")

        let trackerURL = "http://\(trackerHost):\(port)\(trackerPath)"
        let exp = harness.expectObservation(of: trackerURL, testCase: self)

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        // Request reached proxy — not blocked because page is exception-listed
        XCTAssertTrue(
            harness.proxyDidReceive(host: trackerHost, path: trackerPath),
            "Tracker request should reach proxy when page is exception-listed")

        // No surrogate injection
        XCTAssertEqual(
            harness.delegate.detectedSurrogates.count, 0,
            "No surrogate on unprotected domain")

        // Surrogate global should NOT exist (the actual tracker script loaded instead)
        let gaIsDefined = try await evaluateJS(
            "typeof window.ga === 'function'", in: harness.webView) as? Bool
        XCTAssertNotEqual(gaIsDefined, true,
                          "analytics.js surrogate should not have executed")
    }

    // MARK: - Test 4: Second bundled surrogate (gpt.js) injects and executes

    @MainActor
    func testSecondBundledSurrogateGptInjectsAndExecutes() async throws {
        let harness = try await WebViewTestHarness.create(trackerDataJSON: Self.tdsJSON)
        defer { harness.proxy.stop() }

        let trackerHost = "adservices-tracker.org"
        let trackerPath = "/tag/js/gpt.js"
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
        harness.registerContent(host: trackerHost, path: trackerPath, body: "/* blocked */")

        let trackerURL = "http://\(trackerHost):\(port)\(trackerPath)"
        let exp = harness.expectObservation(of: trackerURL, testCase: self)
        exp.expectedFulfillmentCount = 2

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        XCTAssertFalse(
            harness.proxyDidReceive(host: trackerHost, path: trackerPath),
            "Content rules should block the tracker request")

        XCTAssertEqual(
            harness.delegate.detectedSurrogates.count, 1,
            "Exactly one surrogate injection expected")
        if let (detected, host) = harness.delegate.detectedSurrogates.first {
            XCTAssertTrue(detected.isBlocked)
            XCTAssertEqual(host, trackerHost)
        }

        // gpt.js surrogate defines window.googletag as an object
        let googletagIsDefined = try await evaluateJS(
            "typeof window.googletag === 'object'", in: harness.webView) as? Bool
        XCTAssertEqual(googletagIsDefined, true,
                       "gpt.js surrogate should define window.googletag")
    }

}

#endif
