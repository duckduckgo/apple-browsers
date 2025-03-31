//
//  AdClickAttributionRulesSplitterTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import XCTest
@testable import BrowserServicesKit
@testable import TrackerRadarKit

final class AdClickAttributionRulesSplitterTests: XCTestCase {

    func testShouldNotSplitIfThereAreNoTrackerNames() {
        // given
        let trackerData = TrackerData(trackers: [:], entities: [:], domains: [:], cnames: nil)
        let rulesList = ContentBlockerRulesList(name: "", trackerData: nil, fallbackTrackerData: (trackerData, "embedded"))
        let splitter = AdClickAttributionRulesSplitter(rulesList: rulesList, allowlistedTrackerNames: [])

        // when
        let result = splitter.split()

        // then
        XCTAssertNil(result)
    }

    func testShouldNotSplitIfThereAreNoMatchingTrackerNames() {
        // given
        let allowlistedTrackerNames = ["example.com"]
        let trackerData = TrackerData(trackers: [:], entities: [:], domains: [:], cnames: nil)
        let rulesList = ContentBlockerRulesList(name: "", trackerData: nil, fallbackTrackerData: (trackerData, "embedded"))
        let splitter = AdClickAttributionRulesSplitter(rulesList: rulesList, allowlistedTrackerNames: allowlistedTrackerNames)

        // when
        let result = splitter.split()

        // then
        XCTAssertNil(result)
    }

    func testSplitWithSingleTrackerNameShouldMakeOriginalTrackerListEmptyAndAttributionTrackerListEqualToOriginalListBeforeStripping() {
        // given
        let allowlistedTrackerNames = ["example.com"]
        let trackerData = TrackerData(trackers: ["example.com": makeKnownTracker(withName: "example.com",
                                                                                 ownerName: "Example")],
                                      entities: ["Example": makeEntity(withName: "Example", domains: ["example.com"])],
                                      domains: ["example.com": "Example"],
                                      cnames: nil)
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                trackerData: (trackerData, "etag"),
                                                fallbackTrackerData: (trackerData, "embedded"))
        let splitter = AdClickAttributionRulesSplitter(rulesList: rulesList, allowlistedTrackerNames: allowlistedTrackerNames)

        // when
        let result = splitter.split()

        // then
        XCTAssertNotNil(result)

        // original list
        XCTAssertEqual(result!.0.name, rulesList.name)

        let attributionNamePrefix = AdClickAttributionRulesSplitter.Constants.attributionRuleListNamePrefix
        let attributionEtagPrefix = AdClickAttributionRulesSplitter.Constants.attributionRuleListETagPrefix

        XCTAssertEqual(result!.0.trackerData!.etag, attributionEtagPrefix + rulesList.trackerData!.etag)
        XCTAssertEqual(result!.0.fallbackTrackerData.etag, attributionEtagPrefix + rulesList.fallbackTrackerData.etag)

        XCTAssertTrue(result!.0.trackerData!.tds.trackers.isEmpty)
        XCTAssertTrue(result!.0.fallbackTrackerData.tds.trackers.isEmpty)

        // attribution list
        XCTAssertEqual(result!.1.name, attributionNamePrefix + rulesList.name)
        XCTAssertEqual(result!.1.trackerData!.etag, attributionEtagPrefix + rulesList.trackerData!.etag)
        XCTAssertEqual(result!.1.fallbackTrackerData.etag, attributionEtagPrefix + "\(rulesList.fallbackTrackerData.etag)")
        XCTAssertEqual(result!.1.trackerData!.tds, rulesList.trackerData!.tds)
        XCTAssertEqual(result!.1.fallbackTrackerData.tds, rulesList.fallbackTrackerData.tds)

    }

    func testWhenSplittingManyTrackersThenDomainsRelatedToEntitiesArePreserved() {

        // given
        let allowlistedTrackerNames = ["trackerone.com"]
        let trackerData = TrackerData(trackers: ["trackerone.com": makeKnownTracker(withName: "trackerone.com",
                                                                                   ownerName: "Tracker Owner"),
                                                 "trackertwo.com": makeKnownTracker(withName: "trackertwo.com",
                                                                                   ownerName: "Tracker Owner")],
                                      entities: ["Tracker Owner": makeEntity(withName: "Tracker Owner",
                                                                             domains: ["trackerone.com", "example.com"]),
                                                 "Tracker Owner Two": makeEntity(withName: "Tracker Owner Two",
                                                                                 domains: ["trackertwo.com"])],
                                      domains: ["example.com": "Tracker Owner",
                                                "trackerone.com": "Tracker Owner",
                                                "trackertwo.com": "Tracker Owner Two"],
                                      cnames: nil)
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                trackerData: (trackerData, "etag"),
                                                fallbackTrackerData: (trackerData, "embedded"))
        let splitter = AdClickAttributionRulesSplitter(rulesList: rulesList, allowlistedTrackerNames: allowlistedTrackerNames)

        // when
        let result = splitter.split()

        // attribution list

        guard let attributionTDS = result!.1.trackerData else {
            XCTFail("No attribution list found")
            return
        }

        let attributionEtagPrefix = AdClickAttributionRulesSplitter.Constants.attributionRuleListETagPrefix
        XCTAssertEqual(attributionTDS.etag, attributionEtagPrefix + rulesList.trackerData!.etag)

        XCTAssertEqual(attributionTDS.tds.trackers.count, 1)
        XCTAssertEqual(attributionTDS.tds.trackers.first?.key, "trackerone.com")
        XCTAssertEqual(attributionTDS.tds.entities.count, 1)
        XCTAssertEqual(attributionTDS.tds.entities.first?.key, "Tracker Owner")
        XCTAssertEqual(Set(attributionTDS.tds.domains.keys), Set(["example.com", "trackerone.com"]))

    }

    private func makeKnownTracker(withName name: String, ownerName: String) -> KnownTracker {
        KnownTracker(domain: name,
                     defaultAction: .block,
                     owner: .init(name: ownerName, displayName: ownerName, ownedBy: nil),
                     prevalence: 5.0,
                     subdomains: nil,
                     categories: nil,
                     rules: nil)
    }

    private func makeEntity(withName name: String, domains: [String]) -> Entity {
        Entity(displayName: name, domains: domains, prevalence: 5.0)
    }

}
