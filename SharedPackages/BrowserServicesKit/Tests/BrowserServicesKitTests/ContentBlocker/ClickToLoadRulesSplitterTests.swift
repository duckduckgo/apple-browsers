//
//  ClickToLoadRulesSplitterTests.swift
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

final class ClickToLoadRulesSplitterTests: XCTestCase {

    private let ctlTdsName = DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName
    private let mainTdsName = DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName

    func testShoulNotdSplitTrackerDataWithoutCTLActions() {
        // given
        let etag = UUID().uuidString

        let dataSet = buildTrackerDataSet(rawTDS: exampleNonCTLRules, etag: etag)
        XCTAssertNotNil(dataSet)

        let splitRules = splitTrackerDataSet(dataSet: dataSet!)

        // then
        XCTAssertNil(splitRules)

    }

    func testShouldFallbackToCTLEmbeddedIfThereAreNoTrackers() {
        // given
        let etag = UUID().uuidString
        let dataSet = buildTrackerDataSet(rawTDS: exampleCTLRules, etag: etag)
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet", trackerData: nil, fallbackTrackerData: dataSet!)
        let splitter = ClickToLoadRulesSplitter(rulesList: rulesList)

        // when
        let result = splitter.split()

        // then
        XCTAssertNotNil(result)

        XCTAssertNotNil(result?.withBlockCTL)
        XCTAssertNil(result?.withBlockCTL.trackerData)
        XCTAssertNotNil(result?.withBlockCTL.fallbackTrackerData)

        XCTAssertNotNil(result?.withoutBlockCTL)
        XCTAssertNil(result?.withoutBlockCTL.trackerData)
        XCTAssertNotNil(result?.withoutBlockCTL.fallbackTrackerData)

    }

    func testShouldSplitTrackerDataWithCTLActions() {
        // given
        let etag = UUID().uuidString

        let dataSet = buildTrackerDataSet(rawTDS: exampleCTLRules, etag: etag)
        XCTAssertNotNil(dataSet)

        guard let splitRules =  splitTrackerDataSet(dataSet: dataSet!) else {
            XCTFail("Could not split rules")
            return
        }

        // then
        XCTAssertNotNil(splitRules)
        let rulesWithBlockCTL = splitRules.withBlockCTL
        let rulesWithoutBlockCTL = splitRules.withoutBlockCTL

        // withBlockCTL list
        XCTAssertEqual(rulesWithBlockCTL.name, ctlTdsName)
        XCTAssertEqual(rulesWithBlockCTL.trackerData!.etag, "CTL_" + etag)
        XCTAssertEqual(rulesWithBlockCTL.fallbackTrackerData.etag, "CTL_" + etag)
        XCTAssertEqual(rulesWithBlockCTL.trackerData!.tds.trackers.count, 1)
        XCTAssertEqual(rulesWithBlockCTL.trackerData!.tds.trackers.first?.key, "facebook.net")

        // withoutBlockCTL list
        XCTAssertEqual(rulesWithoutBlockCTL.name, mainTdsName)
        XCTAssertEqual(rulesWithoutBlockCTL.trackerData!.etag, "TDS_" + etag)
        XCTAssertEqual(rulesWithoutBlockCTL.fallbackTrackerData.etag, "TDS_" + etag)
        XCTAssertEqual(rulesWithoutBlockCTL.trackerData!.tds.trackers.count, 1)
        XCTAssertEqual(rulesWithoutBlockCTL.trackerData!.tds.trackers.first?.key, "facebook.net")

        let (fbMainRules, mainCTLRuleCount) = getFBTrackerRules(ruleSet: rulesWithoutBlockCTL)
        let (fbCTLRules, ctlCTLRuleCount) = getFBTrackerRules(ruleSet: rulesWithBlockCTL)

        let fbMainRuleCount = fbMainRules!.count
        let fbCTLRuleCount = fbCTLRules!.count

        // ensure both rulesets contains facebook.net rules
        XCTAssert(fbMainRuleCount == 6)
        XCTAssert(fbCTLRuleCount == 9)

        // ensure FB CTL rules include CTL custom actions, and main rules FB do not
        XCTAssert(mainCTLRuleCount == 0)
        XCTAssert(ctlCTLRuleCount == 3)

        // ensure FB CTL rules are the sum of the main rules + CTL custom action rules
        XCTAssert(fbMainRuleCount + ctlCTLRuleCount == fbCTLRuleCount)

    }

    private func makeEntity(withName name: String, domains: [String]) -> Entity {
        Entity(displayName: name, domains: domains, prevalence: 5.0)
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

    private func getFBTrackerRules(ruleSet: ContentBlockerRulesList) -> (rules: [KnownTracker.Rule]?, countCTLActions: Int) {
        let tracker = ruleSet.trackerData?.tds.trackers["facebook.net"]
        return (tracker?.rules, tracker?.countCTLActions ?? 0)
    }

    private func buildTrackerDataSet(rawTDS: String, etag: String) -> TrackerDataManager.DataSet? {
        let fullTDS = rawTDS.data(using: .utf8)!
        let fullTrackerData = (try? JSONDecoder().decode(TrackerData.self, from: fullTDS))!
        return TrackerDataManager.DataSet(tds: fullTrackerData, etag)
    }

    private func splitTrackerDataSet(dataSet: TrackerDataManager.DataSet) -> (withoutBlockCTL: ContentBlockerRulesList, withBlockCTL: ContentBlockerRulesList)? {
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                               trackerData: dataSet,
                                               fallbackTrackerData: dataSet)
        let ctlSplitter = ClickToLoadRulesSplitter(rulesList: rulesList)

        return ctlSplitter.split()
    }

}

private extension KnownTracker {

    var countCTLActions: Int { rules?.filter { $0.action == .blockCTLFB }.count ?? 0 }

}

let exampleCTLRules = """
{
"trackers": {
    "facebook.net": {
        "domain": "facebook.net",
        "owner": {
            "name": "Facebook, Inc.",
            "displayName": "Facebook",
            "privacyPolicy": "https://www.facebook.com/privacy/explanation",
            "url": "https://facebook.com"
        },
        "prevalence": 0.268,
        "fingerprinting": 2,
        "cookies": 0.208,
        "categories": [],
        "default": "ignore",
        "rules": [
            {
                "rule": "facebook\\\\.net/.*/all\\\\.js",
                "surrogate": "fb-sdk.js",
                "action": "block-ctl-fb",
                "fingerprinting": 1,
                "cookies": 0.0000408
            },
            {
                "rule": "facebook\\\\.net/.*/fbevents\\\\.js",
                "fingerprinting": 1,
                "cookies": 0.108
            },
            {
                "rule": "facebook\\\\.net/[a-z_A-Z]+/sdk\\\\.js",
                "surrogate": "fb-sdk.js",
                "action": "block-ctl-fb",
                "fingerprinting": 1,
                "cookies": 0.000334
            },
            {
                "rule": "facebook\\\\.net/signals/config/",
                "fingerprinting": 1,
                "cookies": 0.000101
            },
            {
                "rule": "facebook\\\\.net\\\\/signals\\\\/plugins\\\\/openbridge3\\\\.js",
                "fingerprinting": 1,
                "cookies": 0
            },
            {
                "rule": "facebook\\\\.net/.*/sdk/.*customerchat\\\\.js",
                "fingerprinting": 1,
                "cookies": 0.00000681
            },
            {
                "rule": "facebook\\\\.net\\\\/en_US\\\\/messenger\\\\.Extensions\\\\.js",
                "fingerprinting": 1,
                "cookies": 0
            },
            {
                "rule": "facebook\\\\.net\\\\/en_US\\\\/sdk\\\\/xfbml\\\\.save\\\\.js",
                "fingerprinting": 1,
                "cookies": 0
            },
            {
                "rule": "facebook\\\\.net/",
                "action": "block-ctl-fb"
            }
            ]
    },
},
"entities": {
"Facebook, Inc.": {
  "domains": [
    "facebook.net"
  ],
  "displayName": "Facebook",
  "prevalence": 0.1
}
},
"domains": {
"facebook.net": "Facebook, Inc."
},
"cnames": {}
}
"""

let exampleNonCTLRules = """
{
"trackers": {
"tracker.com": {
  "domain": "tracker.com",
  "default": "block",
  "owner": {
    "name": "Fake Tracking Inc",
    "displayName": "FT Inc",
    "privacyPolicy": "https://tracker.com/privacy",
    "url": "http://tracker.com"
  },
  "source": [
    "DDG"
  ],
  "prevalence": 0.002,
  "fingerprinting": 0,
  "cookies": 0.002,
  "performance": {
    "time": 1,
    "size": 1,
    "cpu": 1,
    "cache": 3
  },
  "categories": [
    "Ad Motivated Tracking",
    "Advertising",
    "Analytics",
    "Third-Party Analytics Marketing"
  ]
}
},
"entities": {
"Fake Tracking Inc": {
  "domains": [
    "tracker.com"
  ],
  "displayName": "Fake Tracking Inc",
  "prevalence": 0.1
}
},
"domains": {
"tracker.com": "Fake Tracking Inc"
}
}
"""
