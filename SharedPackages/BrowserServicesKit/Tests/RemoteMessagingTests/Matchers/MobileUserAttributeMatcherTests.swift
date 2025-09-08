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

    private func setUpUserAttributeMatcher(dismissedMessageIds: [String] = [], isSyncEnabled: Bool = false) {
        matcher = MobileUserAttributeMatcher(
            statisticsStore: mockStatisticsStore,
            variantManager: manager,
            emailManager: emailManager,
            bookmarksCount: 44,
            favoritesCount: 88,
            appTheme: "default",
            isWidgetInstalled: true,
            daysSinceNetPEnabled: 3,
            isPrivacyProEligibleUser: true,
            isPrivacyProSubscriber: true,
            privacyProDaysSinceSubscribed: 5,
            privacyProDaysUntilExpiry: 25,
            privacyProPurchasePlatform: "apple",
            isPrivacyProSubscriptionActive: true,
            isPrivacyProSubscriptionExpiring: false,
            isPrivacyProSubscriptionExpired: false,
            isDuckPlayerOnboarded: false,
            isDuckPlayerEnabled: false,
            dismissedMessageIds: dismissedMessageIds,
            shownMessageIds: [],
            enabledFeatureFlags: [],
            isSyncEnabled: isSyncEnabled
        )
    }
}
