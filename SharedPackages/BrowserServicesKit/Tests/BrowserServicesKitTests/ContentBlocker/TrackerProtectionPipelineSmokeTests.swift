//
//  TrackerProtectionPipelineSmokeTests.swift
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

// Vertical-slice tests covering the production tracker-protection pipeline:
//
//   WKWebView → WKContentRuleList → ContentScopeUserScript →
//   TrackerProtectionSubfeature → TrackerProtectionEventMapper →
//   DetectedRequest delivered to the platform delegate
//
// These exercise the same boundary as the (removed) macOS
// `TrackerProtectionWebKitIntegrationTests` but at the BSK package level
// using `WebViewTestHarness`, avoiding the heavy `Tab` / `WindowsManager`
// scaffolding that previously left those tests hanging on the
// `contentBlockingAssetsPublisher`.

#if os(macOS)

import BrowserServicesKit
import ContentBlocking
import TrackerRadarKit
import WebKit
import XCTest

@available(macOS 14.0, iOS 17.0, *)
final class TrackerProtectionPipelineSmokeTests: XCTestCase {

    // Synthetic TDS:
    //  - `tracker.example.org` — block-default tracker (proxy-safe, not HSTS-preloaded).
    //  - No entry for `cdn.example.net` — exercises the non-tracker third-party path.
    private static let tdsJSON = """
    {
      "trackers": {
        "tracker.example.org": {
          "domain": "tracker.example.org",
          "default": "block",
          "owner": { "name": "Tracker Corp", "displayName": "Tracker Corp" },
          "rules": [
            { "rule": "tracker\\\\.example\\\\.org/.*" }
          ]
        }
      },
      "entities": {
        "Tracker Corp": {
          "domains": ["tracker.example.org"],
          "displayName": "Tracker Corp",
          "prevalence": 0.5
        }
      },
      "domains": {
        "tracker.example.org": "Tracker Corp"
      },
      "cnames": {}
    }
    """

    // MARK: - Test 1: Blocked third-party tracker emits a `.blocked` DetectedRequest

    @MainActor
    func testBlockedThirdPartyTrackerEmitsDetectedRequest() async throws {
        let harness = try await WebViewTestHarness.create(trackerDataJSON: Self.tdsJSON)
        defer { harness.proxy.stop() }

        let trackerHost = "tracker.example.org"
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
        harness.registerContent(host: trackerHost, path: trackerPath, body: "/* tracker */")

        let trackerURL = "http://\(trackerHost):\(port)\(trackerPath)"
        let exp = harness.expectObservation(of: trackerURL, testCase: self)

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        // Content rules blocked the network request — proxy never saw it.
        XCTAssertFalse(
            harness.proxyDidReceive(host: trackerHost, path: trackerPath),
            "Content rules should block the tracker request")

        // Native pipeline still produced a `.blocked` DetectedRequest from the
        // C-S-S `resourceObserved` event.
        XCTAssertEqual(harness.delegate.detectedTrackers.count, 1,
                       "Exactly one blocked tracker expected")
        let detected = try XCTUnwrap(harness.delegate.detectedTrackers.first)
        XCTAssertTrue(detected.isBlocked, "Tracker should be classified as blocked")
        XCTAssertEqual(detected.eTLDplus1, "example.org")
        XCTAssertTrue(detected.url.contains(trackerHost),
                      "DetectedRequest url should reference the tracker host")
    }

    // MARK: - Test 2: Same-site tracker observation is suppressed

    @MainActor
    func testFirstPartyTrackerIsSuppressed() async throws {
        let harness = try await WebViewTestHarness.create(trackerDataJSON: Self.tdsJSON)
        defer { harness.proxy.stop() }

        let host = "tracker.example.org"
        let scriptPath = "/analytics.js"
        let port = harness.proxy.port

        let pageHTML = """
        <html><body>
        <script>
        var s = document.createElement('script');
        s.src = 'http://\(host):\(port)\(scriptPath)';
        document.body.appendChild(s);
        </script>
        </body></html>
        """

        harness.registerContent(host: host, path: "/index.html", body: pageHTML)
        harness.registerContent(host: host, path: scriptPath, body: "/* same-site */")

        let scriptURL = "http://\(host):\(port)\(scriptPath)"
        let exp = harness.expectObservation(of: scriptURL, testCase: self)

        try await harness.load(host: host)
        await fulfillment(of: [exp], timeout: 10)

        // `TrackerProtectionEventMapper.isSameSiteObservation` should drop this:
        // the script's eTLD+1 matches the page's eTLD+1, so neither a
        // tracker nor a third-party DetectedRequest should be produced.
        XCTAssertTrue(harness.delegate.detectedTrackers.isEmpty,
                      "Same-site script should not emit a tracker DetectedRequest. " +
                      "Got \(harness.delegate.detectedTrackers.map(\.url))")
        XCTAssertTrue(harness.delegate.detectedThirdPartyRequests.isEmpty,
                      "Same-site script should not emit a third-party DetectedRequest. " +
                      "Got \(harness.delegate.detectedThirdPartyRequests.map(\.url))")
    }

    // MARK: - Test 3: Non-tracker third-party request is classified as third-party

    @MainActor
    func testNonTrackerThirdPartyRequestEmitsThirdPartyEvent() async throws {
        let harness = try await WebViewTestHarness.create(trackerDataJSON: Self.tdsJSON)
        defer { harness.proxy.stop() }

        let cdnHost = "cdn.example.net"   // intentionally absent from TDS
        let cdnPath = "/lib.js"
        let port = harness.proxy.port

        let pageHTML = """
        <html><body>
        <script>
        var s = document.createElement('script');
        s.src = 'http://\(cdnHost):\(port)\(cdnPath)';
        document.body.appendChild(s);
        </script>
        </body></html>
        """

        harness.registerContent(host: "page.example.com", path: "/index.html", body: pageHTML)
        harness.registerContent(host: cdnHost, path: cdnPath, body: "/* lib */",
                                mimeType: "application/javascript")

        let cdnURL = "http://\(cdnHost):\(port)\(cdnPath)"
        let exp = harness.expectObservation(of: cdnURL, testCase: self)

        try await harness.load(host: "page.example.com")
        await fulfillment(of: [exp], timeout: 10)

        // Not a tracker, not same-site → mapper falls through to
        // `makeThirdPartyRequest` and emits an `.allowed(.otherThirdPartyRequest)` event.
        XCTAssertTrue(harness.delegate.detectedTrackers.isEmpty,
                      "Non-tracker should not be classified as a blocked tracker")

        let cdnEvents = harness.delegate.detectedThirdPartyRequests.filter {
            $0.url.contains(cdnHost)
        }
        XCTAssertEqual(cdnEvents.count, 1,
                       "Expected exactly one third-party event for non-tracker CDN")
        let event = try XCTUnwrap(cdnEvents.first)
        XCTAssertEqual(event.state, .allowed(reason: .otherThirdPartyRequest),
                       "Non-tracker third-party should be allowed with `.otherThirdPartyRequest`")
        XCTAssertEqual(event.eTLDplus1, "example.net")
    }
}

#endif
