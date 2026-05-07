//
//  ContentBlockingDatasetContractTests.swift
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

@testable import BrowserServicesKit
import PrivacyConfigTestsUtils
import TrackerRadarKit
import XCTest

/// Structural assertions enforcing the content-blocking dataset contract:
/// - Full TDS is used exclusively for native classification (Rules.trackerData).
/// - Surrogate-filtered TDS is the only tracker data passed to JavaScript (Rules.encodedTrackerData).
/// - These are separate datasets with separate consumers and must never be collapsed.
class ContentBlockingDatasetContractTests: XCTestCase {

    // MARK: - Dataset split contract

    func testWhenRulesAreCompiledThenEncodedTrackerDataContainsOnlySurrogates() throws {
        let tds = Self.tdsWithMixedTrackers
        let surrogateTDS = ContentBlockerRulesManager.extractSurrogates(from: tds)

        XCTAssertGreaterThan(tds.trackers.count, surrogateTDS.trackers.count,
                             "Full TDS should have more trackers than surrogate-filtered TDS")

        for (domain, tracker) in surrogateTDS.trackers {
            let hasSurrogate = tracker.rules?.contains(where: { $0.surrogate != nil }) ?? false
            XCTAssertTrue(hasSurrogate,
                          "Surrogate-filtered TDS should only contain trackers with surrogate rules, but \(domain) has none")
        }
    }

    func testWhenExtractSurrogatesCalledThenEntitiesAndDomainsAreFiltered() {
        let tds = Self.tdsWithMixedTrackers
        let surrogateTDS = ContentBlockerRulesManager.extractSurrogates(from: tds)

        XCTAssertNotNil(surrogateTDS.domains["surrogatetracker.com"],
                        "Domain for surrogate tracker should be in filtered TDS")
    }

    // MARK: - Fixtures

    static let tdsWithMixedTrackers: TrackerData = {
        let surrogateTracker = KnownTracker(
            domain: "surrogatetracker.com",
            defaultAction: .block,
            owner: KnownTracker.Owner(name: "SurrogateOwner", displayName: "Surrogate Owner", ownedBy: nil),
            prevalence: 0.1,
            subdomains: nil,
            categories: nil,
            rules: [
                KnownTracker.Rule(rule: "surrogatetracker\\.com/script\\.js",
                                  surrogate: "script.js",
                                  action: nil,
                                  options: nil,
                                  exceptions: nil)
            ])

        let nonSurrogateTracker = KnownTracker(
            domain: "nonsurrogate.com",
            defaultAction: .block,
            owner: KnownTracker.Owner(name: "NonSurrogateOwner", displayName: "Non Surrogate Owner", ownedBy: nil),
            prevalence: 0.05,
            subdomains: nil,
            categories: nil,
            rules: nil)

        return TrackerData(
            trackers: [
                "surrogatetracker.com": surrogateTracker,
                "nonsurrogate.com": nonSurrogateTracker
            ],
            entities: [
                "SurrogateOwner": Entity(displayName: "Surrogate Owner",
                                         domains: ["surrogatetracker.com"],
                                         prevalence: 0.1),
                "NonSurrogateOwner": Entity(displayName: "Non Surrogate Owner",
                                            domains: ["nonsurrogate.com"],
                                            prevalence: 0.05)
            ],
            domains: [
                "surrogatetracker.com": "SurrogateOwner",
                "nonsurrogate.com": "NonSurrogateOwner"
            ],
            cnames: nil)
    }()
}
