//
//  DesktopUserAttributeMatcherTests.swift
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

class DesktopUserAttributeMatcherTests: XCTestCase {

    var mockStatisticsStore: MockStatisticsStore!
    var manager: MockVariantManager!
    var emailManager: EmailManager!
    var matcher: DesktopUserAttributeMatcher!
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

        manager = MockVariantManager(isSupportedReturns: true,
                                         currentVariant: MockVariant(name: "zo", weight: 44, isIncluded: { return true }, features: [.dummy]))
        let emailManagerStorage = MockEmailManagerStorage()

        // Set non-empty username and token so that emailManager's isSignedIn returns true
        emailManagerStorage.mockUsername = "username"
        emailManagerStorage.mockToken = "token"

        emailManager = EmailManager(storage: emailManagerStorage)
        setUpUserAttributeMatcher(dismissedDeprecatedMacRemoteMessageIds: ["dismissed-message"])
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        matcher = nil
    }

    // MARK: - PinnedTabs

    func testWhenPinnedTabsMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PinnedTabsMatchingAttribute(value: 3, fallback: nil)),
                       .match)
    }

    func testWhenPinnedTabsDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PinnedTabsMatchingAttribute(value: 2, fallback: nil)),
                       .fail)
    }

    func testWhenPinnedTabsEqualOrLowerThanMaxThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PinnedTabsMatchingAttribute(max: 4, fallback: nil)),
                       .match)
    }

    func testWhenPinnedTabsGreaterThanMaxThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PinnedTabsMatchingAttribute(max: 0, fallback: nil)),
                       .fail)
    }

    func testWhenPinnedTabsLowerThanMinThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PinnedTabsMatchingAttribute(min: 6, fallback: nil)),
                       .fail)
    }

    func testWhenPinnedTabsInRangeThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PinnedTabsMatchingAttribute(min: 2, max: 18, fallback: nil)),
                       .match)
    }

    func testWhenPinnedTabsNotInRangeThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: PinnedTabsMatchingAttribute(min: 9, max: 11, fallback: nil)),
                       .fail)
    }

    // MARK: - CustomHomePage

    func testWhenCustomHomePageMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: CustomHomePageMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenCustomHomePageDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: CustomHomePageMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }

    // MARK: - DuckPlayerOnboarded

    func testWhenDuckPlayerOnboardedMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DuckPlayerOnboardedMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenDuckPlayerOnboardedDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DuckPlayerOnboardedMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }

    // MARK: - DuckPlayerEnabled

    func testWhenDuckPlayerEnabledMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DuckPlayerEnabledMatchingAttribute(value: false, fallback: nil)),
                       .match)
    }

    func testWhenDuckPlayerEnabledDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: DuckPlayerEnabledMatchingAttribute(value: true, fallback: nil)),
                       .fail)
    }

    // MARK: - FreemiumPIRCurrentUser

    func testWhenIsCurrentFreemiumPIRUserEnabledMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIRCurrentUserMatchingAttribute(value: false, fallback: nil)),
                       .match)
    }

    func testWhenIsCurrentFreemiumPIRUserDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: FreemiumPIRCurrentUserMatchingAttribute(value: true, fallback: nil)),
                       .fail)
    }

    // MARK: - DeprecatedMacRemoteMessage

    func testWhenNoDismissedMessageIdsAreProvidedThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: InteractedWithDeprecatedMacRemoteMessageMatchingAttribute(value: [], fallback: nil)
        ), .fail)
    }

    func testWhenNoDismissedMessageIdsMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: InteractedWithDeprecatedMacRemoteMessageMatchingAttribute(value: ["unrelated-message"], fallback: nil)
        ), .fail)
    }

    func testWhenOneDismissedMessageIdMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: InteractedWithDeprecatedMacRemoteMessageMatchingAttribute(value: ["dismissed-message"], fallback: nil)
        ), .match)
    }

    func testWhenTwoDismissedMessageIdsMatchThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(
            matchingAttribute: InteractedWithDeprecatedMacRemoteMessageMatchingAttribute(value: [
                "dismissed-message", "unrelated-message"
            ], fallback: nil)
        ), .match)
    }

    // MARK: -

    private func setUpUserAttributeMatcher(dismissedMessageIds: [String] = [], dismissedDeprecatedMacRemoteMessageIds: [String] = []) {
        matcher = DesktopUserAttributeMatcher(
            statisticsStore: mockStatisticsStore,
            variantManager: manager,
            emailManager: emailManager,
            bookmarksCount: 44,
            favoritesCount: 88,
            appTheme: "default",
            daysSinceNetPEnabled: 3,
            isPrivacyProEligibleUser: true,
            isPrivacyProSubscriber: true,
            privacyProDaysSinceSubscribed: 5,
            privacyProDaysUntilExpiry: 25,
            privacyProPurchasePlatform: "apple",
            isPrivacyProSubscriptionActive: true,
            isPrivacyProSubscriptionExpiring: false,
            isPrivacyProSubscriptionExpired: false,
            dismissedMessageIds: dismissedMessageIds,
            shownMessageIds: [],
            pinnedTabsCount: 3,
            hasCustomHomePage: true,
            isDuckPlayerOnboarded: true,
            isDuckPlayerEnabled: false,
            isCurrentFreemiumPIRUser: false,
            dismissedDeprecatedMacRemoteMessageIds: dismissedDeprecatedMacRemoteMessageIds
        )
    }
}
