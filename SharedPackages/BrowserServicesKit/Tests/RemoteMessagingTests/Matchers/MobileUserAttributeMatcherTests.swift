//
//  MobileUserAttributeMatcherTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import BrowserServicesKitTestsUtils
import Foundation
import RemoteMessagingTestsUtils
import XCTest
@testable import RemoteMessaging

class MobileUserAttributeMatcherTests: XCTestCase {

    var mockStatisticsStore: MockStatisticsStore!
    var mockFeatureDiscovery: MockFeatureDiscovery!
    var manager: MockVariantManager!
    var emailManager: EmailManager!
    var matcher: MobileUserAttributeMatcher!
    var dateYesterday: Date!

    override func setUpWithError() throws {
        let now = Calendar.current.dateComponents(in: .current, from: Date())
        let yesterday = DateComponents(year: now.year, month: now.month, day: now.day! - 1)
        let dateYesterday = Calendar.current.date(from: yesterday)!

        mockStatisticsStore = MockStatisticsStore()
        mockStatisticsStore.atb = "v105-2"
        mockStatisticsStore.appRetentionAtb = "v105-44"
        mockStatisticsStore.searchRetentionAtb = "v105-88"
        mockStatisticsStore.installDate = dateYesterday

        mockFeatureDiscovery = MockFeatureDiscovery()

        manager = MockVariantManager(isSupportedReturns: true,
                                         currentVariant: MockVariant(name: "zo", weight: 44, isIncluded: { return true }, features: [.dummy]))
        let emailManagerStorage = MockEmailManagerStorage()

        // Set non-empty username and token so that emailManager's isSignedIn returns true
        emailManagerStorage.mockUsername = "username"
        emailManagerStorage.mockToken = "token"

        emailManager = EmailManager(storage: emailManagerStorage)
        setUpUserAttributeMatcher()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        matcher = nil
    }

    // MARK: - WidgetAdded

    func testWhenWidgetAddedMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: WidgetAddedMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenWidgetAddedDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: WidgetAddedMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }

    // MARK: - SyncEnabled

    func testWhenSyncEnabledMatchesThenReturnMatch() throws {
        setUpUserAttributeMatcher(isSyncEnabled: true)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: SyncEnabledMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenSyncEnabledDoesNotMatchThenReturnFail() throws {
        setUpUserAttributeMatcher(isSyncEnabled: false)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: SyncEnabledMatchingAttribute(value: true, fallback: nil)),
                       .fail)
    }

    func testWhenSyncDisabledMatchesThenReturnMatch() throws {
        setUpUserAttributeMatcher(isSyncEnabled: false)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: SyncEnabledMatchingAttribute(value: false, fallback: nil)),
                       .match)
    }

    func testWhenSyncDisabledDoesNotMatchThenReturnFail() throws {
        setUpUserAttributeMatcher(isSyncEnabled: true)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: SyncEnabledMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }

    // MARK: - NTPAfterIdleState

    func testWhenNTPAfterIdleStateMatchesSingleValueThenReturnMatch() throws {
        setUpUserAttributeMatcher(ntpAfterIdleState: "eligibleCardShown")
        XCTAssertEqual(matcher.evaluate(matchingAttribute: NTPAfterIdleStateMatchingAttribute(value: ["eligibleCardShown"], fallback: nil)),
                       .match)
    }

    func testWhenNTPAfterIdleStateDoesNotMatchSingleValueThenReturnFail() throws {
        setUpUserAttributeMatcher(ntpAfterIdleState: "eligibleCardHidden")
        XCTAssertEqual(matcher.evaluate(matchingAttribute: NTPAfterIdleStateMatchingAttribute(value: ["eligibleCardShown"], fallback: nil)),
                       .fail)
    }

    func testWhenNTPAfterIdleStateMatchesAnyOfMultipleValuesThenReturnMatch() throws {
        setUpUserAttributeMatcher(ntpAfterIdleState: "eligibleCardHidden")
        XCTAssertEqual(matcher.evaluate(matchingAttribute: NTPAfterIdleStateMatchingAttribute(value: ["eligibleCardShown", "eligibleCardHidden"], fallback: nil)),
                       .match)
    }

    func testWhenNTPAfterIdleStateNotEligibleDoesNotMatchEligibleValuesThenReturnFail() throws {
        setUpUserAttributeMatcher(ntpAfterIdleState: "notEligible")
        XCTAssertEqual(matcher.evaluate(matchingAttribute: NTPAfterIdleStateMatchingAttribute(value: ["eligibleCardShown", "eligibleCardHidden"], fallback: nil)),
                       .fail)
    }

    // MARK: - FreemiumPIREligible

    func testWhenIsFreemiumPIREligibleMatchesThenReturnMatch() throws {
        setUpUserAttributeMatcher(isFreemiumPIREligible: true)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIREligibleMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenIsFreemiumPIREligibleDoesNotMatchThenReturnFail() throws {
        setUpUserAttributeMatcher(isFreemiumPIREligible: false)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIREligibleMatchingAttribute(value: true, fallback: nil)),
                       .fail)
    }

    func testWhenIsNotFreemiumPIREligibleMatchesThenReturnMatch() throws {
        setUpUserAttributeMatcher(isFreemiumPIREligible: false)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIREligibleMatchingAttribute(value: false, fallback: nil)),
                       .match)
    }

    // MARK: - FreemiumPIRDidActivate

    func testWhenFreemiumPIRDidActivateMatchesThenReturnMatch() throws {
        setUpUserAttributeMatcher(isFreemiumPIRActivated: true)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIRDidActivateMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenFreemiumPIRDidNotActivateMatchesThenReturnMatch() throws {
        setUpUserAttributeMatcher(isFreemiumPIRActivated: false)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIRDidActivateMatchingAttribute(value: false, fallback: nil)),
                       .match)
    }

    func testWhenFreemiumPIRDidActivateDoesNotMatchThenReturnFail() throws {
        setUpUserAttributeMatcher(isFreemiumPIRActivated: false)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIRDidActivateMatchingAttribute(value: true, fallback: nil)),
                       .fail)
    }

    // MARK: - FreemiumPIRFirstScanResult

    func testWhenFreemiumPIRFirstScanResultMatchesMatchesFoundThenReturnMatch() throws {
        setUpUserAttributeMatcher(freemiumPIRFirstScanResult: "matchesFound")
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIRFirstScanResultMatchingAttribute(value: "matchesFound", fallback: nil)),
                       .match)
    }

    func testWhenFreemiumPIRFirstScanResultDoesNotMatchThenReturnFail() throws {
        setUpUserAttributeMatcher(freemiumPIRFirstScanResult: "noMatches")
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIRFirstScanResultMatchingAttribute(value: "matchesFound", fallback: nil)),
                       .fail)
    }

    func testWhenFreemiumPIRFirstScanResultMissingThenReturnFail() throws {
        setUpUserAttributeMatcher(freemiumPIRFirstScanResult: nil)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIRFirstScanResultMatchingAttribute(value: "matchesFound", fallback: nil)),
                       .fail)
    }

    // MARK: - PIRCurrentUser

    func testWhenIsCurrentPIRUserMatchesThenReturnMatch() throws {
        setUpUserAttributeMatcher(isCurrentPIRUser: true)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PIRCurrentUserMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenIsCurrentPIRUserDoesNotMatchThenReturnFail() throws {
        setUpUserAttributeMatcher(isCurrentPIRUser: false)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PIRCurrentUserMatchingAttribute(value: true, fallback: nil)),
                       .fail)
    }

    func testWhenIsNotCurrentPIRUserMatchesThenReturnMatch() throws {
        setUpUserAttributeMatcher(isCurrentPIRUser: false)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PIRCurrentUserMatchingAttribute(value: false, fallback: nil)),
                       .match)
    }

    func testWhenIsNotCurrentPIRUserDoesNotMatchThenReturnFail() throws {
        setUpUserAttributeMatcher(isCurrentPIRUser: true)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PIRCurrentUserMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }

    private func setUpUserAttributeMatcher(dismissedMessageIds: [String] = [],
                                           isSyncEnabled: Bool = false,
                                           isFreemiumPIREligible: Bool = false,
                                           isFreemiumPIRActivated: Bool = false,
                                           freemiumPIRFirstScanResult: String? = nil,
                                           isCurrentPIRUser: Bool = false,
                                           ntpAfterIdleState: String = "") {
        matcher = MobileUserAttributeMatcher(
            statisticsStore: mockStatisticsStore,
            featureDiscovery: mockFeatureDiscovery,
            variantManager: manager,
            emailManager: emailManager,
            bookmarksCount: 44,
            favoritesCount: 88,
            appTheme: "default",
            isWidgetInstalled: true,
            daysSinceNetPEnabled: 3,
            isSubscriptionEligibleUser: true,
            isDuckDuckGoSubscriber: true,
            subscriptionDaysSinceSubscribed: 5,
            subscriptionDaysUntilExpiry: 25,
            subscriptionPurchasePlatform: "apple",
            isSubscriptionActive: true,
            isSubscriptionExpiring: false,
            isSubscriptionExpired: false,
            subscriptionFreeTrialActive: false,
            isDuckPlayerOnboarded: false,
            isDuckPlayerEnabled: false,
            dismissedMessageIds: dismissedMessageIds,
            shownMessageIds: [],
            enabledFeatureFlags: [],
            isSyncEnabled: isSyncEnabled,
            shouldShowWinBackOfferUrgencyMessage: false,
            isFreemiumPIREligible: isFreemiumPIREligible,
            isFreemiumPIRActivated: isFreemiumPIRActivated,
            freemiumPIRFirstScanResult: freemiumPIRFirstScanResult,
            isCurrentPIRUser: isCurrentPIRUser,
            ntpAfterIdleState: ntpAfterIdleState
        )
    }
}
