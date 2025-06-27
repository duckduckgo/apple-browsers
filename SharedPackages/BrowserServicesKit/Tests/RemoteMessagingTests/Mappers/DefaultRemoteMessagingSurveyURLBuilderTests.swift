//
//  DefaultRemoteMessagingSurveyURLBuilderTests.swift
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

import XCTest
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import RemoteMessagingTestsUtils
@testable import Subscription
@testable import RemoteMessaging

class DefaultRemoteMessagingSurveyURLBuilderTests: XCTestCase {

    private var standardDefaults: UserDefaults!
    private var autofillUsageStore: AutofillUsageStore!
    private let testStandardName = "remote-messaging-survey-url-builder-tests"

    override func setUpWithError() throws {
        try super.setUpWithError()

        standardDefaults = UserDefaults(suiteName: testStandardName)!
        autofillUsageStore = AutofillUsageStore(standardUserDefaults: standardDefaults, appGroupUserDefaults: nil)
    }

    override func tearDownWithError() throws {
        standardDefaults.removePersistentDomain(forName: testStandardName)

        try super.tearDownWithError()
    }

    func testAddingATBParameter() {
        let builder = buildRemoteMessagingSurveyURLBuilder(atb: "v456-7")
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.atb], to: baseURL)

        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?atb=v456-7")
    }

    func testAddingATBVariantParameter() {
        let builder = buildRemoteMessagingSurveyURLBuilder(variant: "test-variant")
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.atbVariant], to: baseURL)

        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?var=test-variant")
    }

    func testAddingLocaleParameter() {
        let builder = buildRemoteMessagingSurveyURLBuilder(locale: Locale(identifier: "en_NZ"))
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.locale], to: baseURL)

        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?locale=en-NZ")
    }

    func testAddingPrivacyProParameters() {
        let builder = buildRemoteMessagingSurveyURLBuilder()
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.privacyProStatus, .privacyProPlatform, .privacyProPlatform], to: baseURL)

        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?ppro_status=auto_renewable&ppro_platform=apple&ppro_platform=apple")
    }

    func testAddingVPNUsageParameters() {
        let builder = buildRemoteMessagingSurveyURLBuilder(vpnDaysSinceActivation: 10, vpnDaysSinceLastActive: 5)
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.vpnFirstUsed, .vpnLastUsed], to: baseURL)

        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?vpn_first_used=10&vpn_last_used=5")
    }

    func testAddingParametersToURLThatAlreadyHasThem() {
        let builder = buildRemoteMessagingSurveyURLBuilder(vpnDaysSinceActivation: 10, vpnDaysSinceLastActive: 5)
        let baseURL = URL(string: "https://duckduckgo.com?param=test")!
        let finalURL = builder.add(parameters: [.vpnFirstUsed, .vpnLastUsed], to: baseURL)

        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?param=test&vpn_first_used=10&vpn_last_used=5")
    }

    func testAddingLastSearchStateNoneWhenNoLastSearchDate() {
        let builder = buildRemoteMessagingSurveyURLBuilder(lastSearchDate: nil)
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.lastSearchState], to: baseURL)
        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?last_search_state=none")
    }

    func testAddingLastSearchStateNoneWhenLastSearchExactlyEightDaysAgo() {
        let eightDaysAgo = Calendar.current.date(byAdding: .day, value: -8, to: Date())!
        let builder = buildRemoteMessagingSurveyURLBuilder(lastSearchDate: eightDaysAgo)
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.lastSearchState], to: baseURL)
        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?last_search_state=none")
    }

    func testAddingLastSearchStateDayWhenLastSearchIsToday() {
        let builder = buildRemoteMessagingSurveyURLBuilder(lastSearchDate: Date())
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.lastSearchState], to: baseURL)
        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?last_search_state=day")
    }

    func testAddingLastSearchStateDayWhenLastSearchWasYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let builder = buildRemoteMessagingSurveyURLBuilder(lastSearchDate: yesterday)
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.lastSearchState], to: baseURL)
        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?last_search_state=day")
    }

    func testAddingLastSearchStateWeekWhenLastSearchWithin2To6DaysAgo() {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let builder = buildRemoteMessagingSurveyURLBuilder(lastSearchDate: threeDaysAgo)
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.lastSearchState], to: baseURL)
        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?last_search_state=week")
    }

    func testAddingLastSearchStateWeekWhenLastSearchWasSixDaysAgo() {
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        let builder = buildRemoteMessagingSurveyURLBuilder(lastSearchDate: sixDaysAgo)
        let baseURL = URL(string: "https://duckduckgo.com")!
        let finalURL = builder.add(parameters: [.lastSearchState], to: baseURL)
        XCTAssertEqual(finalURL.absoluteString, "https://duckduckgo.com?last_search_state=week")
    }

    func testRefreshLastSearchState_noParamPresent_returnsUnchangedURL() {
        let raw = "https://duckduckgo.com?atb=v1"
        let refreshed = DefaultRemoteMessagingSurveyURLBuilder.refreshLastSearchState(in: raw, lastSearchDate: Date())
        XCTAssertEqual(refreshed, raw)
    }

    func testRefreshLastSearchState_existingParam_updatesValue() {
        let raw = "https://duckduckgo.com?last_search_state=none&foo=bar"
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let refreshed = DefaultRemoteMessagingSurveyURLBuilder.refreshLastSearchState(in: raw, lastSearchDate: twoDaysAgo)

        let components = URLComponents(string: refreshed)!
        let state = components.queryItems?.first(where: { $0.name == "last_search_state" })?.value
        XCTAssertEqual(state, "week")

        XCTAssertTrue(components.queryItems!.contains { $0.name == "foo" && $0.value == "bar"})
    }

    private func buildRemoteMessagingSurveyURLBuilder(
        atb: String = "v123-4",
        variant: String = "var",
        vpnDaysSinceActivation: Int = 2,
        vpnDaysSinceLastActive: Int = 1,
        locale: Locale = Locale(identifier: "en_US"),
        lastSearchDate: Date? = nil
    ) -> DefaultRemoteMessagingSurveyURLBuilder {

        let mockStatisticsStore = MockStatisticsStore()
        mockStatisticsStore.atb = atb
        mockStatisticsStore.variant = variant

        let vpnActivationDateStore = MockVPNActivationDateStore(
            daysSinceActivation: vpnDaysSinceActivation,
            daysSinceLastActive: vpnDaysSinceLastActive
        )

        let subscription = PrivacyProSubscription(productId: "product-id",
                                           name: "product-name",
                                           billingPeriod: .monthly,
                                           startedAt: Date(timeIntervalSince1970: 1000),
                                           expiresOrRenewsAt: Date(timeIntervalSince1970: 2000),
                                           platform: .apple,
                                           status: .autoRenewable,
                                           activeOffers: [])

        standardDefaults.set(lastSearchDate, forKey: AutofillUsageStore.Keys.autofillSearchDauDateKey)

        return DefaultRemoteMessagingSurveyURLBuilder(
            statisticsStore: mockStatisticsStore,
            vpnActivationDateStore: vpnActivationDateStore,
            subscription: subscription,
            localeIdentifier: locale.identifier,
            autofillUsageStore: autofillUsageStore
        )
    }

}

private class MockVPNActivationDateStore: VPNActivationDateProviding {

    var _daysSinceActivation: Int
    var _daysSinceLastActive: Int

    init(daysSinceActivation: Int, daysSinceLastActive: Int) {
        self._daysSinceActivation = daysSinceActivation
        self._daysSinceLastActive = daysSinceLastActive
    }

    func daysSinceActivation() -> Int? {
        return _daysSinceActivation
    }

    func daysSinceLastActive() -> Int? {
        return _daysSinceLastActive
    }

}
