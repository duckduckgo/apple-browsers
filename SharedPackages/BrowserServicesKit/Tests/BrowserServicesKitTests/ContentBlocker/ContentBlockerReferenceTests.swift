//
//  ContentBlockerReferenceTests.swift
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

#if os(macOS)

import BrowserServicesKit
import Common
import ContentBlocking
import Foundation
import os.log
import TrackerRadarKit
import WebKit
import XCTest

/// Data-driven tracker-protection reference tests exercising the full production path:
///   WKWebView → WKContentRuleList → ContentScopeUserScript → TrackerProtectionSubfeature
///   → TrackerProtectionEventMapper → DetectedRequest assertions
///
/// The fixture data uses `.test` TLD domains. Because `.test` is not in the Public Suffix
/// List, `TLD.eTLDplus1` returns nil for those hosts, breaking same-site / same-entity
/// semantics. To preserve faithful PSL behavior the fixtures are normalized at load time:
/// every `.test` occurrence is replaced with `.site`. Using `.site` instead of `.org`
/// avoids HSTS-preloaded domains (e.g. `random.org`) that WebKit upgrades to HTTPS,
/// breaking the loopback proxy tunnel. This preserves all domain relationships
/// (same-host, subdomain, cross-site, entity affiliation) while ensuring real eTLD+1
/// resolution. Normalized names may appear in failure messages.
@available(macOS 14.0, iOS 17.0, *)
@MainActor
final class ContentBlockerReferenceTests: XCTestCase {

    private let tld = TLD()

    func testDomainMatching() async throws {
        let loader = JsonTestDataLoader()

        let tdsRaw = String(
            data: loader.fromJsonFile(
                "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/tracker_radar_reference.json"
            ),
            encoding: .utf8
        )!
        let testsRaw = String(
            data: loader.fromJsonFile(
                "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/domain_matching_tests.json"
            ),
            encoding: .utf8
        )!

        // .test → .site normalization for PSL-faithful execution.
        // .site is preferred over .org to avoid HSTS-preloaded domains like random.org.
        let tdsNormalized = tdsRaw.replacingOccurrences(of: ".test", with: ".site")
        let testsNormalized = testsRaw.replacingOccurrences(of: ".test", with: ".site")

        let tds = try JSONDecoder().decode(TrackerData.self, from: Data(tdsNormalized.utf8))
        let refTests = try JSONDecoder().decode(RefTests.self, from: Data(testsNormalized.utf8))
        let tests = refTests.domainTests.tests

        // Keep original names for failure messages.
        let originalNames = try JSONDecoder()
            .decode(RefTests.self, from: loader.fromJsonFile(
                "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/domain_matching_tests.json"
            ))
            .domainTests.tests.map(\.name)

        // useDefaultDataStore works around a macOS 26 WebKit crash triggered by
        // large WKContentRuleLists + WKUserScript + nonPersistent proxy configuration.
        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: tdsNormalized, useDefaultDataStore: true
        )
        defer {
            harness.proxy.stop()
            harness.webView.configuration.websiteDataStore.proxyConfigurations = []
        }

        var executed = 0
        var skipped = 0

        for (index, test) in tests.enumerated() {
            let name = index < originalNames.count ? originalNames[index] : test.name

            if test.exceptPlatforms?.contains("ios-browser") == true {
                os_log("!!SKIPPING: %s", name)
                skipped += 1
                continue
            }

            os_log("TEST [%d]: %s", index, name)

            harness.proxy.clearReceivedRequests()
            harness.delegate.reset()
            await harness.clearWebKitCaches()

            // --- URL construction (mirrors old appendPathComponent approach) ---

            let httpRequestURL = test.requestURL
                .replacingOccurrences(of: "https://", with: "http://")

            guard let siteURL = URL(string: test.siteURL
                    .replacingOccurrences(of: "https://", with: "http://")),
                  let requestBaseURL = URL(string: httpRequestURL) else {
                XCTFail("\(name): invalid fixture URL")
                continue
            }

            let pageHost = siteURL.host!
            let pagePath = "/iter-\(index)/index.html"

            let resourceURL: URL
            let resourceTag: String
            switch test.requestType {
            case "image":
                resourceURL = requestBaseURL.appendingPathComponent("1.png")
                resourceTag = "<img src=\"\(resourceURL.absoluteString)\">"
            case "script":
                resourceURL = requestBaseURL.appendingPathComponent("1.js")
                // Dynamic creation avoids a macOS 26 WebKit crash triggered by
                // static <script src> + large WKContentRuleList + WKUserScript.
                resourceTag = """
                    <script>
                    var s = document.createElement('script');
                    s.src = '\(resourceURL.absoluteString)';
                    document.body.appendChild(s);
                    </script>
                    """
            default:
                XCTFail("\(name): unsupported requestType '\(test.requestType)'")
                continue
            }

            let resourceHost = resourceURL.host!
            let resourceURLString = resourceURL.absoluteString
            var resourceProxyPath = resourceURL.path
            if let q = resourceURL.query { resourceProxyPath += "?\(q)" }

            let html = """
                <!DOCTYPE html>
                <html>
                <body>
                <h1>Test Page</h1>
                \(resourceTag)
                </body>
                </html>
                """

            let resourceMime = test.requestType == "image"
                ? "image/png" : "application/javascript"
            harness.registerContent(host: pageHost, path: pagePath, body: html)
            harness.registerContent(
                host: resourceHost, path: resourceProxyPath,
                body: "/* resource */", mimeType: resourceMime
            )

            let obsExp = harness.expectObservation(of: resourceURLString, testCase: self)

            try await harness.load(URL(string: "http://\(pageHost)\(pagePath)")!)
            await fulfillment(of: [obsExp], timeout: 10)
            try await Task.sleep(for: .seconds(0.3))

            // --- Classify scenario for assertion template selection ---

            let isSameEntity: Bool = {
                guard let pageEntity = tds.findEntity(forHost: pageHost),
                      let trackerOwner = tds.findTracker(forUrl: httpRequestURL)?.owner,
                      pageEntity.displayName == trackerOwner.name else { return false }
                return true
            }()

            let isSameSite: Bool = {
                guard let p = tld.eTLDplus1(pageHost),
                      let r = tld.eTLDplus1(resourceHost) else { return false }
                return p == r
            }()

            let blockedCount = harness.delegate.detectedTrackers.count
            let allowedCount = harness.delegate.detectedThirdPartyRequests.count

            // --- Apply approved assertion template ---

            if test.expectAction == "block" {
                // Template A: Blocked Third-Party
                XCTAssertTrue(
                    harness.proxyDidReceive(host: pageHost, path: pagePath),
                    "\(name): page must reach proxy")
                XCTAssertFalse(
                    harness.proxyDidReceive(host: resourceHost, path: resourceProxyPath),
                    "\(name): blocked resource must NOT reach proxy")
                XCTAssertEqual(blockedCount, 1,
                    "\(name): expected exactly 1 blocked DetectedRequest")
                XCTAssertTrue(
                    harness.delegate.detectedTrackers.first?.isBlocked == true,
                    "\(name): DetectedRequest must be blocked")
                XCTAssertEqual(allowedCount, 0,
                    "\(name): expected 0 allowed entries for blocked resource")

            } else if test.expectAction == "ignore" {
                XCTAssertTrue(
                    harness.proxyDidReceive(host: pageHost, path: pagePath),
                    "\(name): page must reach proxy")
                XCTAssertTrue(
                    harness.proxyDidReceive(host: resourceHost, path: resourceProxyPath),
                    "\(name): allowed resource must reach proxy")

                if isSameEntity && isSameSite {
                    // Template C: Same-Entity Same-Site — No Event
                    // Same-site observation is silently dropped by the native pipeline.
                    XCTAssertEqual(blockedCount, 0,
                        "\(name): same-entity same-site must not be blocked")
                    XCTAssertEqual(allowedCount, 0,
                        "\(name): same-entity same-site must be silently dropped")

                } else if isSameEntity {
                    // Template D: Same-Entity Cross-Site — Allowed First-Party
                    // Old enforced contract: the resource was allowed to load.
                    // New stronger assertion: resource loads, is not blocked, and
                    // is classified as .allowed(reason: .ownedByFirstParty).
                    XCTAssertEqual(blockedCount, 0,
                        "\(name): same-entity cross-site must not be blocked")
                    XCTAssertEqual(allowedCount, 1,
                        "\(name): same-entity cross-site must produce exactly 1 allowed event")
                    XCTAssertEqual(
                        harness.delegate.detectedThirdPartyRequests.first?.state,
                        .allowed(reason: .ownedByFirstParty),
                        "\(name): must be classified as ownedByFirstParty")

                } else {
                    // Template B: Allowed Known Tracker
                    XCTAssertEqual(blockedCount, 0,
                        "\(name): allowed tracker must not be blocked")
                    XCTAssertEqual(allowedCount, 1,
                        "\(name): expected exactly 1 allowed DetectedRequest")
                    XCTAssertFalse(
                        harness.delegate.detectedThirdPartyRequests.first?.isBlocked == true,
                        "\(name): DetectedRequest must NOT be blocked")
                }

            } else {
                // expectAction == nil: resource is not a known tracker.
                XCTAssertTrue(
                    harness.proxyDidReceive(host: pageHost, path: pagePath),
                    "\(name): page must reach proxy")
                XCTAssertTrue(
                    harness.proxyDidReceive(host: resourceHost, path: resourceProxyPath),
                    "\(name): non-tracker resource must reach proxy")
                XCTAssertEqual(blockedCount, 0,
                    "\(name): non-tracker must not be blocked")

                if isSameSite {
                    // Template E: Non-Tracker Same-Site — No Event
                    XCTAssertEqual(allowedCount, 0,
                        "\(name): same-site non-tracker must be silently dropped")
                } else {
                    // Template F: Non-Tracker Cross-Site
                    for entry in harness.delegate.detectedThirdPartyRequests {
                        XCTAssertEqual(
                            entry.state, .allowed(reason: .otherThirdPartyRequest),
                            "\(name): cross-site non-tracker must be .otherThirdPartyRequest")
                    }
                }
            }

            executed += 1
        }

        os_log("Domain matching tests: %d executed, %d skipped, %d total",
               executed, skipped, tests.count)
        XCTAssertEqual(executed + skipped, tests.count,
                       "All scenarios must be executed or explicitly skipped")
    }
}

#endif
