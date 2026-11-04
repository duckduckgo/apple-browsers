//
//  AutoconsentManagementTests.swift
//  DuckDuckGo
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

import UIKit
import XCTest
import WebExtensions
@testable import DuckDuckGo
@testable import Core
import PixelKit

final class AutoconsentManagementTests: XCTestCase {

    @MainActor
    func testWhenSummaryPixelFiresThenOnePixelIsSentPerSiteRank() {
        var firedPixels: [(name: String, parameters: [String: String])] = []
        PixelKit.setUp(
            dryRun: false,
            appVersion: "1.0.0",
            session: "test",
            defaultHeaders: [:],
            defaults: UserDefaults(suiteName: "test_\(UUID().uuidString)")!
        ) { name, _, parameters, _, _, completion in
            firedPixels.append((name, parameters))
            completion(true, nil)
        }
        defer { PixelKit.tearDown() }

        let management = AutoconsentManagement(eventHub: StubEventHub())
        let parameters = ["consentHeuristicEnabled": "tier1"]
        management.firePixel(pixel: .acInit, siteRank: .top10k, additionalParameters: parameters)
        management.firePixel(pixel: .acInit, siteRank: .other, additionalParameters: parameters)
        management.firePixel(pixel: .popupFound, siteRank: .other, additionalParameters: parameters)
        management.fireSummaryPixel()

        let summaries = firedPixels.filter { $0.name.contains("autoconsent_summary") }.map(\.parameters)
        XCTAssertEqual(summaries.count, 2)
        let top10k = summaries.first { $0["siteRank"] == "top10k" }
        let other = summaries.first { $0["siteRank"] == "other" }
        XCTAssertEqual(top10k?["init"], "1")
        XCTAssertEqual(top10k?["popup-found"], "0")
        XCTAssertEqual(other?["init"], "1")
        XCTAssertEqual(other?["popup-found"], "1")
        XCTAssertEqual(other?["consentHeuristicEnabled"], "tier1")
        XCTAssertTrue(firedPixels.filter { !$0.name.contains("autoconsent_summary") }.allSatisfy { $0.parameters["siteRank"] == nil })
    }

    @MainActor
    func testWhenSummaryPixelFiresThenCPMCoverageIsReportedToEventHub() {
        let eventHub = StubEventHub()
        let management = AutoconsentManagement(eventHub: eventHub)
        management.firePixel(pixel: .acInit, siteRank: .top10k)
        management.firePixel(pixel: .detectedByPatterns, siteRank: .top10k)
        management.firePixel(pixel: .acInit, siteRank: .other)
        management.firePixel(pixel: .acInit, siteRank: .other)
        management.firePixel(pixel: .detectedByPatterns, siteRank: .other)
        management.firePixel(pixel: .detectedByBoth, siteRank: .other)
        management.firePixel(pixel: .detectedByBoth, siteRank: .other)

        management.fireSummaryPixel()
        management.fireSummaryPixel()

        XCTAssertEqual(eventHub.nativeEventCounts, [
            "autoconsent_pages": 3, "autoconsent_pages_top10k": 1,
            "autoconsent_unhandled": 1, "autoconsent_unhandled_top10k": 1,
        ])
    }

    @MainActor
    func testWhenSummaryPixelFiresThenUnhandledDomainsAreReportedToEventHub() {
        let eventHub = StubEventHub()
        let management = AutoconsentManagement(eventHub: eventHub)
        management.firePixel(pixel: .detectedByPatterns, siteRank: .top10k)
        management.firePixel(pixel: .detectedByPatterns, siteRank: .other)
        management.firePixel(pixel: .detectedByPatterns, siteRank: .other)
        management.patternSites = [
            "a": CPMDetectedSite(host: "www.example.com", siteRank: .top10k),
            "b": CPMDetectedSite(host: "shop.example.org", siteRank: .other),
            "c": CPMDetectedSite(host: "example.net", siteRank: .other),
        ]
        management.detectedByBothCache = ["c"]

        management.fireSummaryPixel()

        XCTAssertEqual(eventHub.nativeEventCounts["autoconsent_unhandled_domain"], 2)
        XCTAssertEqual(eventHub.nativeEventCounts["autoconsent_unhandled_domain_top10k"], 1)
        XCTAssertTrue(management.patternSites.isEmpty)
    }

    @MainActor
    func testWhenAppEntersBackgroundThenEventHubIsFlushedAfterTheSummaryIsReported() {
        let eventHub = StubEventHub()
        let management = AutoconsentManagement(eventHub: eventHub)
        management.firePixel(pixel: .acInit, siteRank: .other)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(eventHub.nativeEventCounts, ["autoconsent_pages": 1])
        XCTAssertEqual(eventHub.nativeEventsWhenAppBackgrounded, 1)
        withExtendedLifetime(management) {}
    }

    func testWhenEmbeddedExtensionReportsCoverageThenItIsCountedInEventHub() throws {
        guard #available(iOS 18.4, *) else { throw XCTSkip("Embedded extension requires iOS 18.4") }
        let eventHub = StubEventHub()
        let delegate = IOSAutoconsentMessageHandlerDelegate(eventHub: eventHub)

        delegate.reportCPMCoverage(counts: CPMCoverageCounts(unhandled: 3, pages: 4), siteRank: .top10k,
                                   unhandledHosts: ["www.example.com", "shop.example.com", "example.org"])
        delegate.reportCPMCoverage(counts: CPMCoverageCounts(unhandled: 1, pages: 1), siteRank: nil, unhandledHosts: ["example.net"])

        XCTAssertEqual(eventHub.nativeEventCounts, [
            "autoconsent_pages": 5, "autoconsent_pages_top10k": 4,
            "autoconsent_unhandled": 4, "autoconsent_unhandled_top10k": 3,
            "autoconsent_unhandled_domain": 3, "autoconsent_unhandled_domain_top10k": 2,
        ])
    }

    func testWhenEmbeddedExtensionSendsSummaryPixelThenNothingIsCountedInEventHub() throws {
        guard #available(iOS 18.4, *) else { throw XCTSkip("Embedded extension requires iOS 18.4") }
        let eventHub = StubEventHub()
        let delegate = IOSAutoconsentMessageHandlerDelegate(eventHub: eventHub)

        delegate.sendPixel(PixelInfo(name: "autoconsent_summary", type: "standard", params: [
            "init": "4", "detected-by-patterns": 3, "detected-by-both": "1", "siteRank": "top10k",
        ]))

        XCTAssertTrue(eventHub.nativeEventCounts.isEmpty)
    }
}
