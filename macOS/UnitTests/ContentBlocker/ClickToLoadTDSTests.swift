//
//  ClickToLoadTDSTests.swift
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import TrackerRadarKit
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

private extension KnownTracker {

    var countCTLActions: Int { rules?.filter { $0.action == .blockCTLFB }.count ?? 0 }

}

private extension TrackerData {

    var containsCTLActions: Bool { trackers.values.contains { $0.countCTLActions > 0 } }

}

class ClickToLoadTDSTests: XCTestCase {

    func testEnsureClickToLoadTDSCompiles() throws {

        let provider = AppTrackerDataSetProvider()
        let trackerData = provider.embeddedData
        let etag = provider.embeddedDataEtag
        let trackerManager = TrackerDataManager(etag: etag,
                                         data: trackerData,
                                         embeddedDataProvider: provider)

        try skipUnlessTDSContainsCTLRules(trackerManager)

        let cbrLists = ContentBlockerRulesLists(trackerDataManager: trackerManager, adClickAttribution: MockAttributing())
        let ruleSets = cbrLists.contentBlockerRulesLists
        let tdsName = DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName

        let ctlRules = try XCTUnwrap(ruleSets.first(where: { $0.name == tdsName }), "The TDS carries CTL rules, so a '\(tdsName)' rule list should have been split out")
        let ctlTds = try XCTUnwrap(ctlRules.trackerData?.tds, "'\(tdsName)' rule list is missing its tracker data")

        let builder = ContentBlockerRulesBuilder(trackerData: ctlTds)

        let rules = builder.buildRules(withExceptions: [],
                                       andTemporaryUnprotectedDomains: [],
                                       andTrackerAllowlist: [])

        let data = try JSONEncoder().encode(rules)
        let ruleList = try XCTUnwrap(String(data: data, encoding: .utf8))

        let identifier = UUID().uuidString

        let compiled = expectation(description: "Rules compiled")

        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier,
                                                                encodedContentRuleList: ruleList) { result, error in
            XCTAssertNotNil(result)
            XCTAssertNil(error)
            compiled.fulfill()
        }

        wait(for: [compiled], timeout: 30.0)

        let removed = expectation(description: "Rules removed")

        WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in
            removed.fulfill()
        }

        wait(for: [removed], timeout: 5.0)
    }

    func testClickToLoadTDSSplit() throws {

        let provider = AppTrackerDataSetProvider()

        let trackerManager = TrackerDataManager(
                                    etag: provider.embeddedDataEtag,
                                    data: provider.embeddedData,
                                    embeddedDataProvider: provider
        )

        try skipUnlessTDSContainsCTLRules(trackerManager)

        let cbrLists = ContentBlockerRulesLists(trackerDataManager: trackerManager, adClickAttribution: MockAttributing())
        let ruleSets = cbrLists.contentBlockerRulesLists

        let mainTdsName = DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
        let ctlTdsName = DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName

        let (fbMainRules, mainCTLRuleCount) = getFBTrackerRules(for: mainTdsName, ruleSets: ruleSets)
        let (fbCTLRules, ctlCTLRuleCount) = getFBTrackerRules(for: ctlTdsName, ruleSets: ruleSets)

        let fbMainRuleCount = try XCTUnwrap(fbMainRules, "'\(mainTdsName)' rule list is missing facebook.net rules").count
        let fbCTLRuleCount = try XCTUnwrap(fbCTLRules, "'\(ctlTdsName)' rule list is missing facebook.net rules").count

        // ensure both rulesets contains facebook.net rules
        XCTAssert(fbMainRuleCount > 0)
        XCTAssert(fbCTLRuleCount > 0)

        // ensure FB CTL rules include CTL custom actions, and main rules FB do not
        XCTAssert(mainCTLRuleCount == 0)
        XCTAssert(ctlCTLRuleCount > 0)

        // ensure FB CTL rules are the sum of the main rules + CTL custom action rules
        XCTAssert(fbMainRuleCount + ctlCTLRuleCount == fbCTLRuleCount)

    }

    private func skipUnlessTDSContainsCTLRules(_ trackerDataManager: TrackerDataManager) throws {
        try XCTSkipUnless(trackerDataManager.trackerData.containsCTLActions,
                          "Embedded TDS carries no block-ctl-fb rules - Click to Load is disabled upstream")
    }
}

func getFBTrackerRules(for name: String, ruleSets: [ContentBlockerRulesList]) -> (rules: [KnownTracker.Rule]?, countCTLActions: Int) {
    let tracker = ruleSets.first { $0.name == name }?.trackerData?.tds.trackers["facebook.net"]
    return (tracker?.rules, tracker?.countCTLActions ?? 0)
}
