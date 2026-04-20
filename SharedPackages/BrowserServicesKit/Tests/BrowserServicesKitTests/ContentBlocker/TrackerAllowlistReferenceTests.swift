//
//  TrackerAllowlistReferenceTests.swift
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
import Foundation
import os.log
import PrivacyConfig
import TrackerRadarKit
import WebKit
import XCTest

/// Data-driven tracker-allowlist reference tests exercising the full production path:
///   WKWebView → WKContentRuleList → ContentScopeUserScript → TrackerProtectionSubfeature
///   → TrackerProtectionEventMapper → DetectedRequest assertions
///
/// All fixture domains are `.com` and do not require PSL normalization.
@available(macOS 14.0, iOS 17.0, *)
@MainActor
final class TrackerAllowlistReferenceTests: XCTestCase {

    private struct AllowlistTest: Decodable {
        let description: String
        let site: String
        let request: String
        let isAllowlisted: Bool
        let exceptPlatforms: [String]?
    }

    func testDomainAllowlist() async throws {
        let loader = JsonTestDataLoader()

        let tdsJSON = String(
            data: loader.fromJsonFile(
                "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/tracker_allowlist_tds_reference.json"
            ),
            encoding: .utf8
        )!

        let allowlistData = loader.fromJsonFile(
            "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/tracker_allowlist_reference.json"
        )

        let allowlistJson = try JSONSerialization.jsonObject(with: allowlistData) as! [String: Any]
        let allowlist = PrivacyConfigurationData.TrackerAllowlist(
            json: ["state": "enabled", "settings": ["allowlistedTrackers": allowlistJson]]
        )!

        let tests = try JSONDecoder().decode(
            [AllowlistTest].self,
            from: loader.fromJsonFile(
                "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/tracker_allowlist_matching_tests.json"
            )
        )

        let harness = try await WebViewTestHarness.create(
            trackerDataJSON: tdsJSON,
            trackerAllowlist: allowlist.entries,
            useDefaultDataStore: true
        )
        defer {
            harness.proxy.stop()
            harness.webView.configuration.websiteDataStore.proxyConfigurations = []
        }

        var executed = 0
        var skipped = 0
        var allowedReasons = [String]()

        for (index, test) in tests.enumerated() {
            if test.exceptPlatforms?.contains("ios-browser") == true {
                os_log("!!SKIPPING: %s", test.description)
                skipped += 1
                continue
            }

            os_log("TEST [%d]: %s", index, test.description)

            harness.proxy.clearReceivedRequests()
            harness.delegate.reset()
            await harness.clearWebKitCaches()

            // --- URL construction ---

            var siteURLString = test.site.replacingOccurrences(of: "https://", with: "http://")
            if let u = URL(string: siteURLString), u.path.isEmpty || u.path == "/" {
                siteURLString += "/index.html"
            }

            let requestURLString = test.request.replacingOccurrences(of: "https://", with: "http://")

            guard let siteURL = URL(string: siteURLString),
                  let requestURL = URL(string: requestURLString) else {
                XCTFail("\(test.description): invalid fixture URL")
                continue
            }

            let pageHost = siteURL.host!
            let pagePath = siteURL.path

            let resourceHost = requestURL.host!
            var resourceProxyPath = requestURL.path
            if let q = requestURL.query { resourceProxyPath += "?\(q)" }

            // Dynamic script creation avoids a macOS 26 WebKit crash with
            // static <script src> + large WKContentRuleList + WKUserScript.
            let html = """
                <!DOCTYPE html>
                <html><body>
                <script>
                var s = document.createElement('script');
                s.src = '\(requestURL.absoluteString)';
                document.body.appendChild(s);
                </script>
                </body></html>
                """

            harness.registerContent(host: pageHost, path: pagePath, body: html)
            harness.registerContent(
                host: resourceHost, path: resourceProxyPath,
                body: "/* resource */", mimeType: "application/javascript"
            )

            let obsExp = harness.expectObservation(of: requestURL.absoluteString, testCase: self)

            try await harness.load(siteURL)
            await fulfillment(of: [obsExp], timeout: 10)
            try await Task.sleep(for: .seconds(0.3))

            let blockedCount = harness.delegate.detectedTrackers.count
            let allowedCount = harness.delegate.detectedThirdPartyRequests.count

            // --- Assertions ---

            if !test.isAllowlisted {
                // Blocked: content rules prevent the request from reaching the proxy.
                XCTAssertTrue(
                    harness.proxyDidReceive(host: pageHost, path: pagePath),
                    "\(test.description): page must reach proxy")
                XCTAssertFalse(
                    harness.proxyDidReceive(host: resourceHost, path: resourceProxyPath),
                    "\(test.description): blocked resource must NOT reach proxy")
                XCTAssertEqual(blockedCount, 1,
                    "\(test.description): expected exactly 1 blocked DetectedRequest")
                XCTAssertTrue(
                    harness.delegate.detectedTrackers.first?.isBlocked == true,
                    "\(test.description): DetectedRequest must be blocked")
                XCTAssertEqual(allowedCount, 0,
                    "\(test.description): expected 0 allowed events for blocked resource")

            } else {
                // Allowlisted: content rule exception lets the request through.
                XCTAssertTrue(
                    harness.proxyDidReceive(host: pageHost, path: pagePath),
                    "\(test.description): page must reach proxy")
                XCTAssertTrue(
                    harness.proxyDidReceive(host: resourceHost, path: resourceProxyPath),
                    "\(test.description): allowlisted resource must reach proxy")
                XCTAssertEqual(blockedCount, 0,
                    "\(test.description): allowlisted resource must not be blocked")
                XCTAssertEqual(allowedCount, 1,
                    "\(test.description): expected exactly 1 allowed DetectedRequest")
                XCTAssertFalse(
                    harness.delegate.detectedThirdPartyRequests.first?.isBlocked == true,
                    "\(test.description): DetectedRequest must NOT be blocked")

                if let state = harness.delegate.detectedThirdPartyRequests.first?.state {
                    allowedReasons.append("\(test.description) → \(state)")
                }
            }

            executed += 1
        }

        os_log("Allowlist tests: %d executed, %d skipped, %d total",
               executed, skipped, tests.count)
        XCTAssertEqual(executed + skipped, tests.count,
                       "All scenarios must be executed or explicitly skipped")

        // Log observed allowed reasons for post-run analysis.
        for entry in allowedReasons {
            os_log("ALLOWED REASON: %s", entry)
        }
    }
}

#endif
