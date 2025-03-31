//
//  AdClickAttributionRulesProviderTests.swift
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

// Tests are disabled on iOS due to WKWebView stability issues on the iOS 17.5+ simulator.
#if os(macOS)

import XCTest
import BrowserServicesKit
import os

class MockCompiledRuleListSource: CompiledRuleListsSource {

    var currentRules: [ContentBlockerRulesManager.Rules] {
        [currentMainRules, currentAttributionRules].compactMap { $0 }
    }

    var currentMainRules: ContentBlockerRulesManager.Rules?

    var onCurrentRulesQueried: () -> Void = { }

    var _currentAttributionRules: ContentBlockerRulesManager.Rules?
    var currentAttributionRules: ContentBlockerRulesManager.Rules? {
        get {
            onCurrentRulesQueried()
            return _currentAttributionRules
        }
        set {
            _currentAttributionRules = newValue
        }
    }
}

class AdClickAttributionRulesProviderTests: XCTestCase {

    let feature = MockAttributing()
    let compiledRulesSource = MockCompiledRuleListSource()
    let exceptionsSource = MockContentBlockerRulesExceptionsSource()

    var fakeNewRules: ContentBlockerRulesManager.Rules!

    var provider: AdClickAttributionRulesProvider!

    override func setUp() async throws {
        try? await super.setUp()

        feature.allowlist = [AdClickAttributionFeature.AllowlistEntry(entity: "tracker.com",
                                                                      host: "sub.test.com")]

        compiledRulesSource.currentMainRules = await ContentBlockingRulesHelper().makeFakeRules(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                                                                tdsEtag: "tdsEtag",
                                                                                                tempListId: "tempEtag",
                                                                                                allowListId: nil,
                                                                                                unprotectedSitesHash: nil)

        let attributionName = AdClickAttributionRulesSplitter.blockingAttributionRuleListName(forListNamed: compiledRulesSource.currentMainRules!.name)
        compiledRulesSource.currentAttributionRules = await ContentBlockingRulesHelper().makeFakeRules(name: attributionName,
                                                                                                       tdsEtag: "tdsEtag",
                                                                                                       tempListId: "tempEtag",
                                                                                                       allowListId: nil,
                                                                                                       unprotectedSitesHash: nil)
        XCTAssertNotNil(compiledRulesSource.currentMainRules)
        XCTAssertNotNil(compiledRulesSource.currentAttributionRules)

        fakeNewRules = await ContentBlockingRulesHelper().makeFakeRules(name: compiledRulesSource.currentAttributionRules!.name,
                                                                        tdsEtag: "updatedEtag",
                                                                        tempListId: "updatedEtag",
                                                                        allowListId: nil,
                                                                        unprotectedSitesHash: nil)
        provider = AdClickAttributionRulesProvider(config: feature,
                                                   compiledRulesSource: compiledRulesSource,
                                                   exceptionsSource: exceptionsSource)
    }

    func testWhenAttributionIsRequestedThenRulesArePrepared() {

        let rulesCompiled = expectation(description: "Rules should be compiled")
        provider.requestAttribution(forVendor: "vendor.com") { rules in
            rulesCompiled.fulfill()
            XCTAssertNotNil(rules)
            XCTAssertEqual(rules?.name, AdClickAttributionRulesProvider.Constants.attributedTempRuleListName)

            let tracker = rules?.trackerData.trackers["tracker.com"]
            XCTAssertNotNil(tracker)
            let rule = tracker?.rules?.first
            XCTAssertNotNil(rule)
            XCTAssert(rule?.rule?.contains("sub\\.test\\.com") ?? false)
            XCTAssertEqual(rule?.action, .block)
            XCTAssertEqual(rule?.exceptions?.domains?.first, "vendor.com")
        }

        wait(for: [rulesCompiled], timeout: 5)
    }

    func testWhenAttributionIsRequestedMultipleTimesThenRulesArePreparedOnce() {

        let currentRulesQueried = expectation(description: "Current Rules should be queried")
        currentRulesQueried.expectedFulfillmentCount = 4  // 3 for set up, 1 for compilation
        compiledRulesSource.onCurrentRulesQueried = {
            currentRulesQueried.fulfill()
        }

        let rulesCompiled = expectation(description: "Rules should be compiled")
        rulesCompiled.expectedFulfillmentCount = 3

        var compiledRules: [ContentBlockerRulesManager.Rules] = []
        var identifiers: Set<String> = []
        provider.requestAttribution(forVendor: "vendor.com") { rules in
            rulesCompiled.fulfill()
            compiledRules.append(rules!)
            identifiers.insert(rules!.identifier.stringValue)
        }
        provider.requestAttribution(forVendor: "vendor.com") { rules in
            rulesCompiled.fulfill()
            compiledRules.append(rules!)
            identifiers.insert(rules!.identifier.stringValue)
        }
        provider.requestAttribution(forVendor: "vendor.com") { rules in
            rulesCompiled.fulfill()
            compiledRules.append(rules!)
            identifiers.insert(rules!.identifier.stringValue)
        }

        wait(for: [rulesCompiled, currentRulesQueried], timeout: 5)

        XCTAssertEqual(compiledRules.count, 3)
        XCTAssertEqual(identifiers.count, 1)
        XCTAssert(compiledRules[0].rulesList === compiledRules[1].rulesList)
        XCTAssert(compiledRules[0].rulesList === compiledRules[2].rulesList)
    }

    func testWhenAttributionIsRequestedForMultipleVendorsThenAllRulesArePrepared() {

        let currentRulesQueried = expectation(description: "Current Rules should be queried")
        currentRulesQueried.expectedFulfillmentCount = 5 // 3 for set up, 2 for compilation
        compiledRulesSource.onCurrentRulesQueried = {
            currentRulesQueried.fulfill()
        }

        let rulesCompiled = expectation(description: "Rules should be compiled")
        rulesCompiled.expectedFulfillmentCount = 3

        var compiledRules: [ContentBlockerRulesManager.Rules] = []
        var identifiers: Set<String> = []
        provider.requestAttribution(forVendor: "vendor.com") { rules in // #1
            rulesCompiled.fulfill()
            compiledRules.append(rules!)
            identifiers.insert(rules!.identifier.stringValue)
        }
        provider.requestAttribution(forVendor: "other.com") { rules in // #2
            rulesCompiled.fulfill()
            compiledRules.append(rules!)
            identifiers.insert(rules!.identifier.stringValue)
        }
        provider.requestAttribution(forVendor: "vendor.com") { rules in // #3
            rulesCompiled.fulfill()
            compiledRules.append(rules!)
            identifiers.insert(rules!.identifier.stringValue)
        }

        wait(for: [rulesCompiled, currentRulesQueried], timeout: 10)

        XCTAssertEqual(compiledRules.count, 3)
        XCTAssert(compiledRules[0].rulesList === compiledRules[1].rulesList) // #1 and #3 are returned first
        XCTAssert(compiledRules[0].rulesList !== compiledRules[2].rulesList) // #2 is compiled afterwards
    }

    func testWhenAttributionIsRequestedForMultipleVendorsAndRulesChangeThenAllRulesAreCompiled() {

        let currentRulesQueried = expectation(description: "Current Rules should be queried")
        currentRulesQueried.expectedFulfillmentCount = 6 // 3 for set up, 3 for compilation
        compiledRulesSource.onCurrentRulesQueried = {
            currentRulesQueried.fulfill()
        }

        let rulesCompiled = expectation(description: "Rules should be compiled")
        rulesCompiled.expectedFulfillmentCount = 3

        var compiledRules: [ContentBlockerRulesManager.Rules] = []
        var identifiers: Set<String> = []
        provider.requestAttribution(forVendor: "vendor.com") { rules in // #1
            rulesCompiled.fulfill()
            compiledRules.append(rules!)
            identifiers.insert(rules!.identifier.stringValue)
        }

        // Simulate rule list change
        self.compiledRulesSource.currentAttributionRules = self.fakeNewRules

        provider.requestAttribution(forVendor: "other.com") { rules in // #2
            rulesCompiled.fulfill()
            compiledRules.append(rules!)
            identifiers.insert(rules!.identifier.stringValue)
        }
        provider.requestAttribution(forVendor: "vendor.com") { rules in // #3
            rulesCompiled.fulfill()
            compiledRules.append(rules!)
            identifiers.insert(rules!.identifier.stringValue)
        }

        wait(for: [rulesCompiled, currentRulesQueried], timeout: 10)

        XCTAssertEqual(compiledRules.count, 3)
        XCTAssert(compiledRules[0].rulesList !== compiledRules[1].rulesList)
        XCTAssert(compiledRules[0].rulesList !== compiledRules[2].rulesList)
    }

}

#endif
