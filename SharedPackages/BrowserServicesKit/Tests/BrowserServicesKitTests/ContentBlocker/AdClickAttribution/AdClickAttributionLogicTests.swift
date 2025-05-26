//
//  AdClickAttributionLogicTests.swift
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

import Foundation
import XCTest
import Common
@testable import BrowserServicesKit

final class MockAttributionRulesProvider: AdClickAttributionRulesProviding {

    enum Constants {
        static let globalAttributionRulesListName = "global"
    }

    init() async {
        globalAttributionRules = await ContentBlockingRulesHelper().makeFakeRules(name: Constants.globalAttributionRulesListName,
                                                                                  tdsEtag: "tdsEtag",
                                                                                  tempListId: "tempEtag",
                                                                                  allowListId: nil,
                                                                                  unprotectedSitesHash: nil)

        XCTAssertNotNil(globalAttributionRules)
    }

    var globalAttributionRules: ContentBlockerRulesManager.Rules?

    var onRequestingAttribution: (String, @escaping (ContentBlockerRulesManager.Rules?) -> Void) -> Void = { _, _  in }
    func requestAttribution(forVendor vendor: String,
                            completion: @escaping (ContentBlockerRulesManager.Rules?) -> Void) {
        onRequestingAttribution(vendor, completion)
    }

}

final class MockAdClickAttributionLogicDelegate: AdClickAttributionLogicDelegate {

    var onRequestingRuleApplication: (ContentBlockerRulesManager.Rules?) -> Void = { _ in }

    func attributionLogic(_ logic: AdClickAttributionLogic,
                          didRequestRuleApplication rules: ContentBlockerRulesManager.Rules?,
                          forVendor vendor: String?) {
        onRequestingRuleApplication(rules)
    }
}

// swiftlint:disable weak_delegate
final class AdClickAttributionLogicTests: XCTestCase {

    static let tld = TLD()

    let feature = MockAttributing()
    let mockDelegate = MockAdClickAttributionLogicDelegate()

    func testWhenInitializedThenGlobalRulesApplied() async {

        let mockRulesProvider = await MockAttributionRulesProvider()

        let logic = AdClickAttributionLogic(featureConfig: feature,
                                            rulesProvider: mockRulesProvider,
                                            tld: Self.tld)

        logic.delegate = mockDelegate

        let rulesApplied = expectation(description: "Rules Applied")
        mockDelegate.onRequestingRuleApplication = { rules in
            XCTAssertNotNil(rules)
            XCTAssertEqual(rules?.name, MockAttributionRulesProvider.Constants.globalAttributionRulesListName)
            rulesApplied.fulfill()
        }

        logic.onRulesChanged(latestRules: [mockRulesProvider.globalAttributionRules!])

        await fulfillment(of: [rulesApplied], timeout: 0.1)
    }

    func testWhenAttributionDetectedThenNewRulesAreRequestedAndApplied() async {

        let mockAttributedRules = await ContentBlockingRulesHelper().makeFakeRules(name: "attributed")
        let mockDetection = AdClickAttributionDetection(feature: feature,
                                                        tld: Self.tld)

        let mockRulesProvider = await MockAttributionRulesProvider()

        let logic = AdClickAttributionLogic(featureConfig: feature,
                                            rulesProvider: mockRulesProvider,
                                            tld: Self.tld)

        logic.delegate = mockDelegate
        logic.onRulesChanged(latestRules: [mockRulesProvider.globalAttributionRules!])

        // Regular navigation, call handler immediately
        let navigationAllowed = expectation(description: "Navigation allowed")
        logic.onProvisionalNavigation { navigationAllowed.fulfill() }
        await fulfillment(of: [navigationAllowed], timeout: 0.1)

        // Expect
        // 1. Call to request attribution for found vendor

        var attributedRulesPrepared: (ContentBlockerRulesManager.Rules?) -> Void = { _ in XCTFail("Expected actual handler") }
        mockRulesProvider.onRequestingAttribution = { vendor, completion in
            XCTAssertEqual(vendor, "example.com")
            attributedRulesPrepared = completion
        }

        logic.attributionDetection(mockDetection, didDetectVendor: "example.com")

        // 2. Wait with N requests till rules are ready.
        var requestCompletedCount = 0
        logic.onProvisionalNavigation { requestCompletedCount += 1 }
        logic.onProvisionalNavigation { requestCompletedCount += 1 }

        // Nothing completed yet...
        XCTAssertEqual(requestCompletedCount, 0)

        // 3. Apply rules once ready (when callback is called)
        let rulesApplied = expectation(description: "Rules Applied")
        mockDelegate.onRequestingRuleApplication = { rules in
            XCTAssertNotNil(rules?.name)
            XCTAssertEqual(rules?.name, mockAttributedRules?.name)
            rulesApplied.fulfill()
        }

        // 4. Expect navigation to happen once rules are prepared
        attributedRulesPrepared(mockAttributedRules)

        // Requests completed now
        XCTAssertEqual(requestCompletedCount, 2)

        await fulfillment(of: [rulesApplied], timeout: 0.5)
    }

    func testWhenAttributionDetectedThenPreviousOneIsReplaced() async {

        let mockDetection = AdClickAttributionDetection(feature: feature,
                                                        tld: Self.tld)
        let mockRulesProvider = await MockAttributionRulesProvider()

        let mockAttributedRules = await ContentBlockingRulesHelper().makeFakeRules(name: "attributed")

        let logic = AdClickAttributionLogic(featureConfig: feature,
                                            rulesProvider: mockRulesProvider,
                                            tld: Self.tld)

        logic.delegate = mockDelegate
        logic.onRulesChanged(latestRules: [mockRulesProvider.globalAttributionRules!])
        logic.onProvisionalNavigation { }

        // Expect
        // 1. Call to request attribution for found vendor

        // - Mock rules creation
        mockRulesProvider.onRequestingAttribution = { vendor, completion in
            XCTAssertEqual(vendor, "example.com")
            completion(mockAttributedRules)
        }

        let rulesApplied = expectation(description: "Rules Applied")
        mockDelegate.onRequestingRuleApplication = { rules in
            XCTAssertNotNil(rules?.name)
            XCTAssertEqual(rules?.name, mockAttributedRules?.name)
            rulesApplied.fulfill()
        }
        // -

        logic.attributionDetection(mockDetection, didDetectVendor: "example.com")
        await fulfillment(of: [rulesApplied], timeout: 0.2)

        // 2. These should be executed immediately
        var requestCompletedCount = 0
        logic.onProvisionalNavigation { requestCompletedCount += 1 }
        logic.onProvisionalNavigation { requestCompletedCount += 1 }

        XCTAssertEqual(requestCompletedCount, 2)

        logic.onDidFinishNavigation(host: "test.com")

        // - Mock new rules creation
        let mockNewAttributedRules = await ContentBlockingRulesHelper().makeFakeRules(name: "newAttributed")

        mockRulesProvider.onRequestingAttribution = { vendor, completion in
            XCTAssertEqual(vendor, "other.com")
            completion(mockNewAttributedRules)
        }

        let newRulesApplied = expectation(description: "New Rules Applied")
        mockDelegate.onRequestingRuleApplication = { rules in
            XCTAssertNotNil(rules?.name)
            XCTAssertEqual(rules?.name, mockNewAttributedRules?.name)
            newRulesApplied.fulfill()
        }
        // -

        // 3. Simulate new navigation.
        logic.onProvisionalNavigation { requestCompletedCount += 1 }
        // 4. And new attribution detection.
        logic.attributionDetection(mockDetection, didDetectVendor: "other.com")
        await fulfillment(of: [newRulesApplied], timeout: 0.2)

        logic.onProvisionalNavigation { requestCompletedCount += 1 }
        logic.onProvisionalNavigation { requestCompletedCount += 1 }

        // Requests completed now
        XCTAssertEqual(requestCompletedCount, 5)
    }
}

final class AdClickAttributionLogicHelper {

    static let tld = TLD()
    static let feature = MockAttributing()

    static func prepareLogic(attributedVendorHost: String,
                             eventReporting: EventMapping<AdClickAttributionEvents>? = nil) async -> (logic: AdClickAttributionLogic,
                                                                     startOfAttribution: Date) {
        let mockAttributedRules = await ContentBlockingRulesHelper().makeFakeRules(name: "attributed")
        let mockRulesProvider = await MockAttributionRulesProvider()
        let mockDetection = AdClickAttributionDetection(feature: feature,
                                                        tld: tld)

        mockRulesProvider.onRequestingAttribution = { vendor, completion in
            XCTAssertEqual(vendor, attributedVendorHost)
            completion(mockAttributedRules)
        }

        let logic = AdClickAttributionLogic(featureConfig: feature,
                                            rulesProvider: mockRulesProvider,
                                            tld: tld,
                                            eventReporting: eventReporting)

        logic.attributionDetection(mockDetection, didDetectVendor: attributedVendorHost)

        logic.onDidFinishNavigation(host: "sub.\(attributedVendorHost)")

        let startOfAttribution: Date!
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, let rules) = logic.state {
            XCTAssertEqual(rules.identifier, mockAttributedRules?.identifier)
            startOfAttribution = session.attributionStartedAt
        } else {
            XCTFail("Attribution should be present")
            startOfAttribution = Date()
        }

        return (logic, startOfAttribution)
    }
}

final class AdClickAttributionLogicTimeoutTests: XCTestCase {

    func testWhenAttributionIsActiveThenTotalTimeoutApplies() async {
        let (logic, startOfAttribution) = await AdClickAttributionLogicHelper.prepareLogic(attributedVendorHost: "example.com")
        let feature = AdClickAttributionLogicHelper.feature

        logic.onProvisionalNavigation(completion: {},
                                      currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution = logic.state { } else {
            XCTFail("Attribution should be present")
        }

        logic.onProvisionalNavigation(completion: {},
                                      currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration))
        if case AdClickAttributionLogic.State.noAttribution = logic.state { } else {
            XCTFail("Attribution should be forgotten")
        }
    }

    func testWhenAttributionIsInactiveThenNavigationalTimeoutApplies() async {
        let (logic, startOfAttribution) = await AdClickAttributionLogicHelper.prepareLogic(attributedVendorHost: "example.com")
        let feature = AdClickAttributionLogicHelper.feature

        logic.onDidFinishNavigation(host: "example.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution = logic.state { } else {
            XCTFail("Attribution should be present")
        }

        logic.onProvisionalNavigation(completion: {},
                                      currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, _) = logic.state {
            XCTAssertNil(session.leftAttributionContextAt)
        } else {
            XCTFail("Attribution should be present")
        }

        var leftAttributionContextAt: Date! = nil
        logic.onDidFinishNavigation(host: "other.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, _) = logic.state {
            leftAttributionContextAt = session.leftAttributionContextAt
            XCTAssertNotNil(leftAttributionContextAt)
        } else {
            XCTFail("Attribution should be present")
        }

        logic.onProvisionalNavigation(completion: {},
                                      currentTime: leftAttributionContextAt.addingTimeInterval(feature.navigationExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution = logic.state { } else {
            XCTFail("Attribution should be present")
        }

        logic.onProvisionalNavigation(completion: {},
                                      currentTime: leftAttributionContextAt.addingTimeInterval(feature.navigationExpiration))
        if case AdClickAttributionLogic.State.noAttribution = logic.state { } else {
            XCTFail("Attribution should be forgotten")
        }
    }

    func testWhenAttributionIsReappliedThenTotalTimeoutApplies() async {
        let (logic, startOfAttribution) = await AdClickAttributionLogicHelper.prepareLogic(attributedVendorHost: "example.com")
        let feature = AdClickAttributionLogicHelper.feature

        logic.onDidFinishNavigation(host: "example.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution = logic.state { } else {
            XCTFail("Attribution should be present")
        }

        logic.onDidFinishNavigation(host: "other.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, _) = logic.state {
            XCTAssertNotNil(session.leftAttributionContextAt)
        } else {
            XCTFail("Attribution should be present")
        }

        logic.onProvisionalNavigation(completion: {},
                                      currentTime: startOfAttribution.addingTimeInterval(feature.navigationExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, _) = logic.state {
            XCTAssertNotNil(session.leftAttributionContextAt)
        } else {
            XCTFail("Attribution should be present")
        }

        logic.onDidFinishNavigation(host: "example.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.navigationExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, _) = logic.state {
            XCTAssertNil(session.leftAttributionContextAt)
        } else {
            XCTFail("Attribution should be present")
        }

        logic.onProvisionalNavigation(completion: {},
                                      currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution = logic.state { } else {
            XCTFail("Attribution should be present")
        }

        logic.onDidFinishNavigation(host: "example.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution = logic.state { } else {
            XCTFail("Attribution should be present")
        }

        logic.onProvisionalNavigation(completion: {},
                                      currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration))
        if case AdClickAttributionLogic.State.noAttribution = logic.state { } else {
            XCTFail("Attribution should be forgotten")
        }
    }

    func testWhenAttributionIsReappliedThenNavigationalTimeoutResetsForNextInactiveState() async {
        let (logic, startOfAttribution) = await AdClickAttributionLogicHelper.prepareLogic(attributedVendorHost: "example.com")
        let feature = AdClickAttributionLogicHelper.feature

        logic.onDidFinishNavigation(host: "example.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution = logic.state { } else {
            XCTFail("Attribution should be present")
        }

        var lastTimeOfLeavingAttributionSite: Date?
        logic.onDidFinishNavigation(host: "other.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, _) = logic.state {
            XCTAssertNotNil(session.leftAttributionContextAt)
            lastTimeOfLeavingAttributionSite = session.leftAttributionContextAt
        } else {
            XCTFail("Attribution should be present")
        }

        logic.onDidFinishNavigation(host: "example.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.navigationExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, _) = logic.state {
            XCTAssertNil(session.leftAttributionContextAt)
        } else {
            XCTFail("Attribution should be present")
        }

        logic.onDidFinishNavigation(host: "other.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, _) = logic.state {
            XCTAssertNotNil(session.leftAttributionContextAt)
            XCTAssertNotEqual(lastTimeOfLeavingAttributionSite, session.leftAttributionContextAt)
            lastTimeOfLeavingAttributionSite = session.leftAttributionContextAt
        } else {
            XCTFail("Attribution should be present")
        }

        logic.onProvisionalNavigation(completion: {},
                                      currentTime: lastTimeOfLeavingAttributionSite!.addingTimeInterval(feature.navigationExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, _) = logic.state {
            XCTAssertNotNil(session.leftAttributionContextAt)
        } else {
            XCTFail("Attribution should be present")
        }

        logic.onDidFinishNavigation(host: "something.com",
                                    currentTime: lastTimeOfLeavingAttributionSite!.addingTimeInterval(feature.navigationExpiration - 1))
        if case AdClickAttributionLogic.State.activeAttribution(_, let session, _) = logic.state {
            XCTAssertNotNil(session.leftAttributionContextAt)
        } else {
            XCTFail("Attribution should be present")
        }

        logic.onProvisionalNavigation(completion: {},
                                      currentTime: lastTimeOfLeavingAttributionSite!.addingTimeInterval(feature.navigationExpiration))
        if case AdClickAttributionLogic.State.noAttribution = logic.state { } else {
            XCTFail("Attribution should be forgotten")
        }
    }

}

final class AdClickAttributionLogicStateInheritingTests: XCTestCase {

    static let tld = TLD()
    let feature = MockAttributing()

    func testWhenAttributionIsInheritedThenOriginalStartTimeIsUsedForTotalTimeout() async {
        let (logic, startOfAttribution) = await AdClickAttributionLogicHelper.prepareLogic(attributedVendorHost: "example.com")
        let feature = AdClickAttributionLogicHelper.feature
        let rules = await ContentBlockingRulesHelper().makeFakeRules(name: "attributed")!

        logic.onDidFinishNavigation(host: "example.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))

        if case AdClickAttributionLogic.State.activeAttribution = logic.state { } else {
            XCTFail("Attribution should be present")
        }

        let inheritedSession = AdClickAttributionLogic.SessionInfo(start: startOfAttribution.addingTimeInterval(-1))
        logic.applyInheritedAttribution(state: .activeAttribution(vendor: "example.com",
                                                                  session: inheritedSession,
                                                                  rules: rules))

        logic.onDidFinishNavigation(host: "example.com",
                                    currentTime: startOfAttribution.addingTimeInterval(feature.totalExpiration - 1))

        if case AdClickAttributionLogic.State.noAttribution = logic.state { } else {
            XCTFail("Attribution should be forgotten")
        }
    }

    func testWhenInactiveAttributionIsInheritedThenItIsIgnored() async {
        let mockRulesProvider = await MockAttributionRulesProvider()
        let rules = await ContentBlockingRulesHelper().makeFakeRules(name: "attributed")!

        let logic = AdClickAttributionLogic(featureConfig: feature,
                                            rulesProvider: mockRulesProvider,
                                            tld: Self.tld)

        if case AdClickAttributionLogic.State.noAttribution = logic.state { } else {
            XCTFail("Attribution should be present")
        }

        let inactiveSession = AdClickAttributionLogic.SessionInfo(start: Date(),
                                                                   leftContextAt: Date())
        logic.applyInheritedAttribution(state: .activeAttribution(vendor: "example.com",
                                                                  session: inactiveSession,
                                                                  rules: rules))

        if case AdClickAttributionLogic.State.noAttribution = logic.state { } else {
            XCTFail("Attribution should be forgotten")
        }
    }

}

final class AdClickAttributionLogicConfigUpdateTests: XCTestCase {

    static let tld = TLD()

    let feature = MockAttributing()
    let mockDelegate = MockAdClickAttributionLogicDelegate()

    func testWhenTDSUpdatesThenAttributedRulesAreRefreshed() async {
        let mockAttributedRules = await ContentBlockingRulesHelper().makeFakeRules(name: "attributed")
        let mockDetection = AdClickAttributionDetection(feature: feature,
                                                        tld: Self.tld)

        let mockRulesProvider = await MockAttributionRulesProvider()

        let logic = AdClickAttributionLogic(featureConfig: feature,
                                            rulesProvider: mockRulesProvider,
                                            tld: Self.tld)

        logic.delegate = mockDelegate

        mockRulesProvider.onRequestingAttribution = { vendor, completion in
            XCTAssertEqual(vendor, "example.com")
            completion(mockAttributedRules)
        }

        let rulesApplied = expectation(description: "Rules Applied")
        mockDelegate.onRequestingRuleApplication = { rules in
            XCTAssertNotNil(rules?.name)
            XCTAssertEqual(rules?.name, mockAttributedRules?.name)
            rulesApplied.fulfill()
        }

        logic.attributionDetection(mockDetection, didDetectVendor: "example.com")
        await fulfillment(of: [rulesApplied], timeout: 0.1)

        // - Prepare callbacks for update
        let updatedAttributedRules = await ContentBlockingRulesHelper().makeFakeRules(name: "attributed_updated")
        mockRulesProvider.onRequestingAttribution = { vendor, completion in
            XCTAssertEqual(vendor, "example.com")
            completion(updatedAttributedRules)
        }

        let rulesUpdated = expectation(description: "Rules Updated")
        mockDelegate.onRequestingRuleApplication = { rules in
            XCTAssertNotNil(rules?.name)
            XCTAssertEqual(rules?.name, updatedAttributedRules?.name)
            rulesUpdated.fulfill()
        }
        // -

        let updatedTDSRules = await ContentBlockingRulesHelper().makeFakeRules(name: "newTDS",
                                                                               tdsEtag: UUID().uuidString)
        XCTAssertNotNil(updatedTDSRules)

        logic.onRulesChanged(latestRules: [updatedTDSRules!])
        await fulfillment(of: [rulesUpdated], timeout: 0.1)
    }
}

// swiftlint:enable weak_delegate
