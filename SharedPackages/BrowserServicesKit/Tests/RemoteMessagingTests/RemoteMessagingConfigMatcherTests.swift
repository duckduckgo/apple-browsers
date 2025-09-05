//
//  RemoteMessagingConfigMatcherTests.swift
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import Common
import BrowserServicesKitTestsUtils
import RemoteMessagingTestsUtils
import XCTest
@testable import RemoteMessaging

class RemoteMessagingConfigMatcherTests: XCTestCase {

    private var matcher: RemoteMessagingConfigMatcher!

    override func setUpWithError() throws {
        let emailManagerStorage = MockEmailManagerStorage()

        // Set non-empty username and token so that emailManager's isSignedIn returns true
        emailManagerStorage.mockUsername = "username"
        emailManagerStorage.mockToken = "token"

        let emailManager = EmailManager(storage: emailManagerStorage)
        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    emailManager: emailManager,
                    bookmarksCount: 10,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false
                ),
                percentileStore: MockRemoteMessagePercentileStore(),
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: []
        )
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        matcher = nil
    }

    func testWhenEmptyConfigThenReturnNull() throws {
        let emptyConfig = RemoteConfigModel(messages: [], rules: [])

        XCTAssertNil(matcher.evaluate(remoteConfig: emptyConfig))
    }

    func testWhenNoMatchingRulesThenReturnFirstMessage() throws {
        let noRulesRemoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: []),
                                                          mediumMessage(matchingRules: [], exclusionRules: [])],
                                               rules: [])
        XCTAssertEqual(matcher.evaluate(remoteConfig: noRulesRemoteConfig), mediumMessage(matchingRules: [], exclusionRules: []))
    }

    func testWhenNotExistingRuleThenReturnSkipMessage() throws {
        let noRulesRemoteConfig = RemoteConfigModel(messages: [mediumMessage(matchingRules: [1], exclusionRules: []),
                                                          mediumMessage(matchingRules: [], exclusionRules: [])],
                                               rules: [])

        XCTAssertEqual(matcher.evaluate(remoteConfig: noRulesRemoteConfig), mediumMessage(matchingRules: [], exclusionRules: []))
    }

    func testWhenNoMessagesThenReturnNull() throws {
        let os = ProcessInfo().operatingSystemVersion
        let noRulesRemoteConfig = RemoteConfigModel(messages: [], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [
                OSMatchingAttribute(min: "0.0", max: String(os.majorVersion + 1), fallback: nil)
            ])
        ])

        XCTAssertNil(matcher.evaluate(remoteConfig: noRulesRemoteConfig))
    }

    func testWhenDeviceDoesNotMatchMessageRulesThenReturnNull() throws {
        let os = ProcessInfo().operatingSystemVersion
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: []),
            mediumMessage(matchingRules: [1], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [
                OSMatchingAttribute(min: "0.0", max: String(os.majorVersion - 1), fallback: nil)
            ])
        ])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenNoMatchingRulesThenReturnFirstNonExcludedMessage() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [], exclusionRules: [2]),
            mediumMessage(matchingRules: [], exclusionRules: [3])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [
                LocaleMatchingAttribute(value: [LocaleMatchingAttribute.localeIdentifierAsJsonFormat(Locale.current.identifier)], fallback: nil)
            ]),
            RemoteConfigRule(id: 3, targetPercentile: nil, attributes: [EmailEnabledMatchingAttribute(value: false, fallback: nil)])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [], exclusionRules: [3]))
    }

    func testWhenMatchingMessageShouldBeExcludedThenReturnNull() {
        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersion, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false
                ),
                percentileStore: MockRemoteMessagePercentileStore(),
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: [])

        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: [2])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [LocaleMatchingAttribute(value: ["en-US"], fallback: nil)])
        ])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenMatchingMessageShouldBeExcludedByOneOfMultipleRulesThenReturnNull() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: [4]),
            mediumMessage(matchingRules: [1], exclusionRules: [2, 3]),
            mediumMessage(matchingRules: [1], exclusionRules: [2, 3, 4]),
            mediumMessage(matchingRules: [1], exclusionRules: [2, 4]),
            mediumMessage(matchingRules: [1], exclusionRules: [4])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [
                EmailEnabledMatchingAttribute(value: true, fallback: nil), BookmarksMatchingAttribute(max: 10, fallback: nil)
            ]),
            RemoteConfigRule(id: 3, targetPercentile: nil, attributes: [
                EmailEnabledMatchingAttribute(value: true, fallback: nil), BookmarksMatchingAttribute(max: 10, fallback: nil)
            ]),
            RemoteConfigRule(id: 4, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]),
            RemoteConfigRule(id: 5, targetPercentile: nil, attributes: [EmailEnabledMatchingAttribute(value: true, fallback: nil)])
        ])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenMultipleMatchingMessagesAndSomeExcludedThenReturnFirstNonExcludedMatch() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: [2]),
            mediumMessage(matchingRules: [1], exclusionRules: [2]),
            mediumMessage(matchingRules: [1], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [
                LocaleMatchingAttribute(value: [LocaleMatchingAttribute.localeIdentifierAsJsonFormat(Locale.current.identifier)], fallback: nil)
            ])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: []))
    }

    func testWhenMessageMatchesAndExclusionRuleFailsThenReturnMessage() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: [2])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [EmailEnabledMatchingAttribute(value: false, fallback: nil)])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: [2]))
    }

    func testWhenDeviceMatchesMessageRulesThenReturnFirstMatch() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: []))
    }

    func testWhenDeviceMatchesMessageRulesForOneOfMultipleMessagesThenReturnMatch() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [2], exclusionRules: []),
            mediumMessage(matchingRules: [1, 2], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [EmailEnabledMatchingAttribute(value: false, fallback: nil)])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1, 2], exclusionRules: []))
    }

    func testWhenUserDismissedMessagesAndDeviceMatchesMultipleMessagesThenReturnFirstMatchNotDismissed() {
        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 10,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false
                ),
                percentileStore: MockRemoteMessagePercentileStore(),
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: ["1"])

        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: []),
            mediumMessage(id: "2", matchingRules: [1], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(id: "2", matchingRules: [1], exclusionRules: []))
    }

    func testWhenDeviceMatchesAnyRuleThenReturnFirstMatch() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1, 2], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [LocaleMatchingAttribute(value: [Locale.current.identifier], fallback: nil)]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [OSMatchingAttribute(min: "0", max: "100", fallback: nil)])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1, 2], exclusionRules: []))
    }

    func testWhenDeviceDoesNotMatchAnyRuleThenReturnNull() {
        let os = ProcessInfo().operatingSystemVersion
        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersion, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false
                ),
                percentileStore: MockRemoteMessagePercentileStore(),
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: [])

        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1, 2], exclusionRules: []),
            mediumMessage(matchingRules: [1, 2], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [
                OSMatchingAttribute(min: "0.0", max: String(os.majorVersion - 1), fallback: nil)
            ]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [
                OSMatchingAttribute(min: "0.0", max: String(os.majorVersion - 1), fallback: nil)
            ])
        ])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenDeviceMatchesMessageRules_AndIsPartOfPercentile_ThenReturnMatch() {
        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.defaultPercentage = 0.1

        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersion, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false
                ),
                percentileStore: percentileStore,
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: [])

        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(
                id: 1,
                targetPercentile: RemoteConfigTargetPercentile(before: 0.3),
                attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]
            )
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: []))
    }

    func testWhenDeviceMatchesMessageRules_AndIsNotPartOfPercentile_ThenReturnNull() {
        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.defaultPercentage = 0.5

        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersion, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false
                ),
                percentileStore: percentileStore,
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: [])

        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(
                id: 1,
                targetPercentile: RemoteConfigTargetPercentile(before: 0.3),
                attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]
            )
        ])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenDeviceExcludesMessageRules_AndIsPartOfPercentile_ThenReturnNull() {
        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.defaultPercentage = 0.3

        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersion, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false
                ),
                percentileStore: percentileStore,
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: [])

        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [], exclusionRules: [1])
        ], rules: [
            RemoteConfigRule(
                id: 1,
                targetPercentile: RemoteConfigTargetPercentile(before: 0.5),
                attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]
            )
        ])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenDeviceExcludesMessageRules_AndIsNotPartOfPercentile_ThenReturnMatch() {
        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.defaultPercentage = 0.6

        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersion, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false
                ),
                percentileStore: percentileStore,
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: [])

        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [], exclusionRules: [1])
        ], rules: [
            RemoteConfigRule(
                id: 1,
                targetPercentile: RemoteConfigTargetPercentile(before: 0.5),
                attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)]
            )
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [], exclusionRules: [1]))
    }

    func testWhenUnknownRuleFailsThenReturnNull() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: []),
            mediumMessage(matchingRules: [1], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [UnknownMatchingAttribute(fallback: false)])
        ])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenUnknownRuleMatchesThenReturnFirstMatch() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: []),
            mediumMessage(id: "2", matchingRules: [1], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [UnknownMatchingAttribute(fallback: true)])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: []))
    }

    func mediumMessage(id: String = "1", matchingRules: [Int], exclusionRules: [Int]) -> RemoteMessageModel {
        return RemoteMessageModel(id: id,
                                  content: .medium(titleText: "title", descriptionText: "description", placeholder: .announce),
                                  matchingRules: matchingRules,
                                  exclusionRules: exclusionRules,
                                  isMetricsEnabled: true
        )
    }
}
