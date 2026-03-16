//
//  DefaultTrackerProtectionDataSourceTests.swift
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

import XCTest
@testable import BrowserServicesKit
import TrackerRadarKit
import WebKit

@MainActor
final class DefaultTrackerProtectionDataSourceTests: XCTestCase {

    private let helper = ContentBlockingRulesHelper()

    // MARK: - Tracker data fixtures

    private func mainTDS() -> TrackerData {
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: KnownTracker.Owner(name: "Tracker Inc", displayName: "Tracker Inc", ownedBy: nil),
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)
        let entity = Entity(displayName: "Tracker Inc", domains: ["tracker.com"], prevalence: 0.1)
        return TrackerData(trackers: ["tracker.com": tracker],
                           entities: ["Tracker Inc": entity],
                           domains: ["tracker.com": "Tracker Inc"],
                           cnames: nil)
    }

    private func ctlTDS() -> TrackerData {
        let ctlRule = KnownTracker.Rule(rule: "facebook\\.net/.*sdk\\.js", surrogate: nil, action: .blockCTLFB, options: nil, exceptions: nil)
        let fbTracker = KnownTracker(domain: "facebook.net",
                                     defaultAction: .ignore,
                                     owner: KnownTracker.Owner(name: "Facebook Inc", displayName: "Facebook", ownedBy: nil),
                                     prevalence: 0.5,
                                     subdomains: nil,
                                     categories: nil,
                                     rules: [ctlRule])
        let entity = Entity(displayName: "Facebook", domains: ["facebook.net", "facebook.com"], prevalence: 0.5)
        return TrackerData(trackers: ["facebook.net": fbTracker],
                           entities: ["Facebook Inc": entity],
                           domains: ["facebook.net": "Facebook Inc", "facebook.com": "Facebook Inc"],
                           cnames: nil)
    }

    private func attributionTDS() -> TrackerData {
        let tracker = KnownTracker(domain: "ad-attribution.example",
                                   defaultAction: .block,
                                   owner: KnownTracker.Owner(name: "Ad Attribution Inc", displayName: "Ad Attribution", ownedBy: nil),
                                   prevalence: 0.05,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)
        let entity = Entity(displayName: "Ad Attribution", domains: ["ad-attribution.example"], prevalence: 0.05)
        return TrackerData(trackers: ["ad-attribution.example": tracker],
                           entities: ["Ad Attribution Inc": entity],
                           domains: ["ad-attribution.example": "Ad Attribution Inc"],
                           cnames: nil)
    }

    private func makeFakeRules(name: String, trackerData: TrackerData) async -> ContentBlockerRulesManager.Rules? {
        let identifier = ContentBlockerRulesIdentifier(name: name,
                                                       tdsEtag: UUID().uuidString,
                                                       tempListId: nil,
                                                       allowListId: nil,
                                                       unprotectedSitesHash: nil)
        let builder = ContentBlockerRulesBuilder(trackerData: trackerData)
        let rules = builder.buildRules()
        guard let data = try? JSONEncoder().encode(rules),
              let ruleList = String(data: data, encoding: .utf8),
              let compiled = try? await WKContentRuleListStore.default()?.compileContentRuleList(
                  forIdentifier: identifier.stringValue, encodedContentRuleList: ruleList
              ) else { return nil }
        return .init(name: name, rulesList: compiled,
                     trackerData: trackerData, encodedTrackerData: "",
                     etag: "", identifier: identifier)
    }

    // MARK: - Merge behavior

    func testMergedTrackerData_includesCTLTrackers() async {
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainTDS()
        )!
        let ctlRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
            trackerData: ctlTDS()
        )!
        let mock = StubCompiledRuleListsSource(rules: [mainRules, ctlRules])

        let dataSource = DefaultTrackerProtectionDataSource(
            contentBlockingManager: mock,
            additionalRuleLists: [DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName]
        )

        let merged = dataSource.trackerData
        XCTAssertNotNil(merged)
        XCTAssertNotNil(merged?.trackers["tracker.com"], "Main TDS trackers should be present")
        XCTAssertNotNil(merged?.trackers["facebook.net"], "CTL trackers should be merged in")
        XCTAssertNotNil(merged?.entities["Facebook Inc"], "CTL entities should be merged in")
        XCTAssertEqual(merged?.domains["facebook.net"], "Facebook Inc")

        let fbTracker = merged?.trackers["facebook.net"]
        XCTAssertNotNil(fbTracker?.rules?.first(where: { $0.action == .blockCTLFB }),
                        "block-ctl-fb rule should be present in merged data")
    }

    func testMergedTrackerData_mainOnlyWhenNoAdditionalLists() async {
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainTDS()
        )!
        let ctlRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
            trackerData: ctlTDS()
        )!
        let mock = StubCompiledRuleListsSource(rules: [mainRules, ctlRules])

        let dataSource = DefaultTrackerProtectionDataSource(contentBlockingManager: mock)

        let data = dataSource.trackerData
        XCTAssertNotNil(data?.trackers["tracker.com"])
        XCTAssertNil(data?.trackers["facebook.net"],
                     "CTL trackers should NOT be present when no additional lists specified")
    }

    func testMergedTrackerData_handlesAbsentClickToLoadList() async {
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainTDS()
        )!
        let mock = StubCompiledRuleListsSource(rules: [mainRules])

        let dataSource = DefaultTrackerProtectionDataSource(
            contentBlockingManager: mock,
            additionalRuleLists: [DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName]
        )

        let data = dataSource.trackerData
        XCTAssertNotNil(data, "Should still return main tracker data when additional list is absent")
        XCTAssertNotNil(data?.trackers["tracker.com"])
        XCTAssertNil(data?.trackers["facebook.net"])
    }

    func testEncodedTrackerData_includesCTLRules() async {
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainTDS()
        )!
        let ctlRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
            trackerData: ctlTDS()
        )!
        let mock = StubCompiledRuleListsSource(rules: [mainRules, ctlRules])

        let dataSource = DefaultTrackerProtectionDataSource(
            contentBlockingManager: mock,
            additionalRuleLists: [DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName]
        )

        guard let encoded = dataSource.encodedTrackerData else {
            XCTFail("encodedTrackerData should not be nil")
            return
        }
        XCTAssertTrue(encoded.contains("facebook.net"), "Encoded data should contain CTL tracker domain")
        XCTAssertTrue(encoded.contains("tracker.com"), "Encoded data should contain main tracker domain")
    }

    func testEncodedTrackerData_unchangedWhenNoAdditionalLists() async {
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainTDS()
        )!
        let mock = StubCompiledRuleListsSource(rules: [mainRules])

        let dataSource = DefaultTrackerProtectionDataSource(contentBlockingManager: mock)

        guard let encoded = dataSource.encodedTrackerData else {
            XCTFail("encodedTrackerData should not be nil")
            return
        }
        XCTAssertTrue(encoded.contains("tracker.com"))
        XCTAssertFalse(encoded.contains("facebook.net"),
                       "Encoded data should not include CTL data when no additional lists")
    }

    func testMergedTrackerData_includesBothCTLAndAttributionTrackers() async {
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainTDS()
        )!
        let ctlRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
            trackerData: ctlTDS()
        )!
        let attrRules = await makeFakeRules(
            name: AdClickAttributionRulesSplitter.blockingAttributionRuleListName(
                forListNamed: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
            ),
            trackerData: attributionTDS()
        )!
        let mock = StubCompiledRuleListsSource(rules: [mainRules, ctlRules, attrRules])

        let dataSource = DefaultTrackerProtectionDataSource(
            contentBlockingManager: mock,
            additionalRuleLists: [
                DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
                AdClickAttributionRulesSplitter.blockingAttributionRuleListName(
                    forListNamed: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
                ),
            ]
        )

        let merged = dataSource.trackerData
        XCTAssertNotNil(merged)
        XCTAssertNotNil(merged?.trackers["tracker.com"], "Main TDS tracker should be present")
        XCTAssertNotNil(merged?.trackers["facebook.net"], "CTL tracker should be merged in")
        XCTAssertNotNil(merged?.trackers["ad-attribution.example"], "Attribution tracker should be merged in")
        XCTAssertEqual(merged?.domains["ad-attribution.example"], "Ad Attribution Inc")
        XCTAssertNotNil(merged?.entities["Ad Attribution Inc"])
    }

    func testMergedTrackerData_attributionAbsent_noError() async {
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainTDS()
        )!
        let ctlRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
            trackerData: ctlTDS()
        )!
        let mock = StubCompiledRuleListsSource(rules: [mainRules, ctlRules])

        let dataSource = DefaultTrackerProtectionDataSource(
            contentBlockingManager: mock,
            additionalRuleLists: [
                DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
                AdClickAttributionRulesSplitter.blockingAttributionRuleListName(
                    forListNamed: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
                ),
            ]
        )

        let merged = dataSource.trackerData
        XCTAssertNotNil(merged, "Should still return merged data when attribution list is absent")
        XCTAssertNotNil(merged?.trackers["tracker.com"])
        XCTAssertNotNil(merged?.trackers["facebook.net"], "CTL trackers should still merge")
        XCTAssertNil(merged?.trackers["ad-attribution.example"],
                     "Attribution tracker should not appear when list is absent")
    }

    func testMergedTrackerData_usesSnapshotForAllLookups() async {
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainTDS()
        )!
        let ctlRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
            trackerData: ctlTDS()
        )!

        let mutatingMock = MutatingStubCompiledRuleListsSource(
            firstSnapshot: [mainRules, ctlRules],
            subsequentSnapshot: [mainRules]
        )

        let dataSource = DefaultTrackerProtectionDataSource(
            contentBlockingManager: mutatingMock,
            additionalRuleLists: [DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName]
        )

        let merged = dataSource.trackerData
        XCTAssertNotNil(merged?.trackers["facebook.net"],
                        "CTL tracker should be present because mergedTrackerData uses the first snapshot")
        XCTAssertGreaterThanOrEqual(mutatingMock.accessCount, 1)
    }

    func testMergedTrackerData_preservesCnamesFromMainSet() async {
        var mainData = mainTDS()
        mainData = TrackerData(trackers: mainData.trackers,
                               entities: mainData.entities,
                               domains: mainData.domains,
                               cnames: ["cname.example.com": "tracker.com"])
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainData
        )!
        let ctlRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
            trackerData: ctlTDS()
        )!
        let mock = StubCompiledRuleListsSource(rules: [mainRules, ctlRules])

        let dataSource = DefaultTrackerProtectionDataSource(
            contentBlockingManager: mock,
            additionalRuleLists: [DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName]
        )

        let merged = dataSource.trackerData
        XCTAssertEqual(merged?.cnames?["cname.example.com"], "tracker.com",
                       "Cnames from main TDS should be preserved in merge")
    }
}

// MARK: - Test helpers

private class StubCompiledRuleListsSource: CompiledRuleListsSource {
    let rules: [ContentBlockerRulesManager.Rules]

    init(rules: [ContentBlockerRulesManager.Rules]) {
        self.rules = rules
    }

    var currentRules: [ContentBlockerRulesManager.Rules] { rules }

    var currentMainRules: ContentBlockerRulesManager.Rules? {
        rules.first(where: { $0.name == DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName })
    }

    var currentAttributionRules: ContentBlockerRulesManager.Rules? { nil }
}

/// Returns different rule arrays on successive `.currentRules` accesses.
/// Used to verify that `mergedTrackerData()` takes a single snapshot
/// and derives all lookups from it.
private class MutatingStubCompiledRuleListsSource: CompiledRuleListsSource {
    private let firstSnapshot: [ContentBlockerRulesManager.Rules]
    private let subsequentSnapshot: [ContentBlockerRulesManager.Rules]
    private(set) var accessCount = 0

    init(firstSnapshot: [ContentBlockerRulesManager.Rules],
         subsequentSnapshot: [ContentBlockerRulesManager.Rules]) {
        self.firstSnapshot = firstSnapshot
        self.subsequentSnapshot = subsequentSnapshot
    }

    var currentRules: [ContentBlockerRulesManager.Rules] {
        accessCount += 1
        return accessCount == 1 ? firstSnapshot : subsequentSnapshot
    }

    var currentMainRules: ContentBlockerRulesManager.Rules? {
        currentRules.first(where: { $0.name == DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName })
    }

    var currentAttributionRules: ContentBlockerRulesManager.Rules? { nil }
}
