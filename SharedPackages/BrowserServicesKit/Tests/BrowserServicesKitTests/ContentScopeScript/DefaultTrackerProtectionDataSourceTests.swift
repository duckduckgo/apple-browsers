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

    private func mainTDS() -> TrackerData {
        let surrogateRule = KnownTracker.Rule(rule: "tracker\\.com/analytics\\.js",
                                              surrogate: "tracker-surrogate.js",
                                              action: .block, options: nil, exceptions: nil)
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: KnownTracker.Owner(name: "Tracker Inc", displayName: "Tracker Inc", ownedBy: nil),
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: [surrogateRule])
        let entity = Entity(displayName: "Tracker Inc", domains: ["tracker.com"], prevalence: 0.1)
        return TrackerData(trackers: ["tracker.com": tracker],
                           entities: ["Tracker Inc": entity],
                           domains: ["tracker.com": "Tracker Inc"],
                           cnames: nil)
    }

    private func ctlTDS() -> TrackerData {
        let ctlRule = KnownTracker.Rule(rule: "facebook\\.net/.*sdk\\.js", surrogate: "fb-sdk-surrogate.js", action: .blockCTLFB, options: nil, exceptions: nil)
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

    func testTrackerData_usesMainDatasetEvenWhenCTLDatasetExists() async {
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

        XCTAssertNotNil(dataSource.trackerData)
        XCTAssertNotNil(dataSource.trackerData?.trackers["tracker.com"], "Main tracker should be present")
        XCTAssertNil(dataSource.trackerData?.trackers["facebook.net"], "Non-main trackers should not be merged for surrogate injection")
    }

    func testSurrogateFilteredTrackerData_derivedFromMainDatasetOnly() async {
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

        XCTAssertNotNil(dataSource.surrogateFilteredTrackerData)
        XCTAssertNotNil(dataSource.surrogateFilteredTrackerData?.trackers["tracker.com"])
        XCTAssertNil(dataSource.surrogateFilteredTrackerData?.trackers["facebook.net"])
    }

    func testWhenMainDatasetMissing_thenValuesAreNil() async {
        let ctlRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName,
            trackerData: ctlTDS()
        )!
        let mock = StubCompiledRuleListsSource(rules: [ctlRules])

        let dataSource = DefaultTrackerProtectionDataSource(contentBlockingManager: mock)

        XCTAssertNil(dataSource.trackerData)
        XCTAssertNil(dataSource.surrogateFilteredTrackerData)
    }

    func testMainTrackerData_usesSingleSnapshot() async {
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainTDS()
        )!

        let mutatingMock = MutatingStubCompiledRuleListsSource(
            firstSnapshot: [mainRules],
            subsequentSnapshot: []
        )

        let dataSource = DefaultTrackerProtectionDataSource(contentBlockingManager: mutatingMock)

        XCTAssertNotNil(dataSource.trackerData?.trackers["tracker.com"])
        XCTAssertEqual(mutatingMock.accessCount, 1)
    }

    func testTrackerData_preservesCnamesFromMainSet() async {
        var mainData = mainTDS()
        mainData = TrackerData(trackers: mainData.trackers,
                               entities: mainData.entities,
                               domains: mainData.domains,
                               cnames: ["cname.example.com": "tracker.com"])
        let mainRules = await makeFakeRules(
            name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
            trackerData: mainData
        )!
        let mock = StubCompiledRuleListsSource(rules: [mainRules])

        let dataSource = DefaultTrackerProtectionDataSource(contentBlockingManager: mock)
        XCTAssertEqual(dataSource.trackerData?.cnames?["cname.example.com"], "tracker.com",
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
