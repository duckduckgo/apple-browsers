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
                    featureDiscovery: MockFeatureDiscovery(),
                    variantManager: MockVariantManager(),
                    emailManager: emailManager,
                    bookmarksCount: 10,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isSubscriptionEligibleUser: false,
                    isDuckDuckGoSubscriber: false,
                    subscriptionDaysSinceSubscribed: -1,
                    subscriptionDaysUntilExpiry: -1,
                    subscriptionPurchasePlatform: nil,
                    isSubscriptionActive: false,
                    isSubscriptionExpiring: false,
                    isSubscriptionExpired: false,
                    subscriptionFreeTrialActive: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false,
                    shouldShowWinBackOfferUrgencyMessage: false
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
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]),
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
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersionMajorMinorPatch, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    featureDiscovery: MockFeatureDiscovery(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isSubscriptionEligibleUser: false,
                    isDuckDuckGoSubscriber: false,
                    subscriptionDaysSinceSubscribed: -1,
                    subscriptionDaysUntilExpiry: -1,
                    subscriptionPurchasePlatform: nil,
                    isSubscriptionActive: false,
                    isSubscriptionExpiring: false,
                    isSubscriptionExpired: false,
                    subscriptionFreeTrialActive: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false,
                    shouldShowWinBackOfferUrgencyMessage: false
                ),
                percentileStore: MockRemoteMessagePercentileStore(),
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: [])

        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: [2])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]),
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
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [
                EmailEnabledMatchingAttribute(value: true, fallback: nil), BookmarksMatchingAttribute(max: 10, fallback: nil)
            ]),
            RemoteConfigRule(id: 3, targetPercentile: nil, attributes: [
                EmailEnabledMatchingAttribute(value: true, fallback: nil), BookmarksMatchingAttribute(max: 10, fallback: nil)
            ]),
            RemoteConfigRule(id: 4, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]),
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
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]),
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
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [EmailEnabledMatchingAttribute(value: false, fallback: nil)])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: [2]))
    }

    func testWhenDeviceMatchesMessageRulesThenReturnFirstMatch() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: []))
    }

    func testWhenDeviceMatchesMessageRulesForOneOfMultipleMessagesThenReturnMatch() {
        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [2], exclusionRules: []),
            mediumMessage(matchingRules: [1, 2], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]),
            RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [EmailEnabledMatchingAttribute(value: false, fallback: nil)])
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1, 2], exclusionRules: []))
    }

    func testWhenUserDismissedMessagesAndDeviceMatchesMultipleMessagesThenReturnFirstMatchNotDismissed() {
        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    featureDiscovery: MockFeatureDiscovery(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 10,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isSubscriptionEligibleUser: false,
                    isDuckDuckGoSubscriber: false,
                    subscriptionDaysSinceSubscribed: -1,
                    subscriptionDaysUntilExpiry: -1,
                    subscriptionPurchasePlatform: nil,
                    isSubscriptionActive: false,
                    isSubscriptionExpiring: false,
                    isSubscriptionExpired: false,
                    subscriptionFreeTrialActive: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false,
                    shouldShowWinBackOfferUrgencyMessage: false
                ),
                percentileStore: MockRemoteMessagePercentileStore(),
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: ["1"])

        let remoteConfig = RemoteConfigModel(messages: [
            mediumMessage(matchingRules: [1], exclusionRules: []),
            mediumMessage(id: "2", matchingRules: [1], exclusionRules: [])
        ], rules: [
            RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
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
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersionMajorMinorPatch, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    featureDiscovery: MockFeatureDiscovery(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isSubscriptionEligibleUser: false,
                    isDuckDuckGoSubscriber: false,
                    subscriptionDaysSinceSubscribed: -1,
                    subscriptionDaysUntilExpiry: -1,
                    subscriptionPurchasePlatform: nil,
                    isSubscriptionActive: false,
                    isSubscriptionExpiring: false,
                    isSubscriptionExpired: false,
                    subscriptionFreeTrialActive: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false,
                    shouldShowWinBackOfferUrgencyMessage: false
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
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersionMajorMinorPatch, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    featureDiscovery: MockFeatureDiscovery(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isSubscriptionEligibleUser: false,
                    isDuckDuckGoSubscriber: false,
                    subscriptionDaysSinceSubscribed: -1,
                    subscriptionDaysUntilExpiry: -1,
                    subscriptionPurchasePlatform: nil,
                    isSubscriptionActive: false,
                    isSubscriptionExpiring: false,
                    isSubscriptionExpired: false,
                    subscriptionFreeTrialActive: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false,
                    shouldShowWinBackOfferUrgencyMessage: false
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
                attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]
            )
        ])

        XCTAssertEqual(matcher.evaluate(remoteConfig: remoteConfig), mediumMessage(matchingRules: [1], exclusionRules: []))
    }

    func testWhenDeviceMatchesMessageRules_AndIsNotPartOfPercentile_ThenReturnNull() {
        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.defaultPercentage = 0.5

        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersionMajorMinorPatch, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    featureDiscovery: MockFeatureDiscovery(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isSubscriptionEligibleUser: false,
                    isDuckDuckGoSubscriber: false,
                    subscriptionDaysSinceSubscribed: -1,
                    subscriptionDaysUntilExpiry: -1,
                    subscriptionPurchasePlatform: nil,
                    isSubscriptionActive: false,
                    isSubscriptionExpiring: false,
                    isSubscriptionExpired: false,
                    subscriptionFreeTrialActive: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false,
                    shouldShowWinBackOfferUrgencyMessage: false
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
                attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]
            )
        ])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenDeviceExcludesMessageRules_AndIsPartOfPercentile_ThenReturnNull() {
        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.defaultPercentage = 0.3

        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersionMajorMinorPatch, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    featureDiscovery: MockFeatureDiscovery(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isSubscriptionEligibleUser: false,
                    isDuckDuckGoSubscriber: false,
                    subscriptionDaysSinceSubscribed: -1,
                    subscriptionDaysUntilExpiry: -1,
                    subscriptionPurchasePlatform: nil,
                    isSubscriptionActive: false,
                    isSubscriptionExpiring: false,
                    isSubscriptionExpired: false,
                    subscriptionFreeTrialActive: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false,
                    shouldShowWinBackOfferUrgencyMessage: false
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
                attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]
            )
        ])

        XCTAssertNil(matcher.evaluate(remoteConfig: remoteConfig))
    }

    func testWhenDeviceExcludesMessageRules_AndIsNotPartOfPercentile_ThenReturnMatch() {
        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.defaultPercentage = 0.6

        matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                deviceAttributeMatcher: DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersionMajorMinorPatch, locale: "en-US", formFactor: "phone"),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    featureDiscovery: MockFeatureDiscovery(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isSubscriptionEligibleUser: false,
                    isDuckDuckGoSubscriber: false,
                    subscriptionDaysSinceSubscribed: -1,
                    subscriptionDaysUntilExpiry: -1,
                    subscriptionPurchasePlatform: nil,
                    isSubscriptionActive: false,
                    isSubscriptionExpiring: false,
                    isSubscriptionExpired: false,
                    subscriptionFreeTrialActive: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false,
                    shouldShowWinBackOfferUrgencyMessage: false
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
                attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)]
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

    // MARK: - List Items Filtering Tests

    func testWhenMessageWithItemsPassesAndAllItemsPassRules_ThenReturnMessage() {
        // GIVEN
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [1]), // Will pass
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [1])  // Will pass
        ]
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)
        let remoteConfig = RemoteConfigModel(messages: [expectedMessage], rules: [rule1])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage)
    }

    func testWhenMessageWithItemsPassesButAllItemsFailRules_ThenReturnNull() {
        // GIVEN
        // Valid rule applied at message level
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        // Invalid rule applied at item level
        let rule2 = RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [OSMatchingAttribute(value: "nonexistent_os", fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [2]), // Will fail
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [2])  // Will fail
        ]
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1, rule2])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertNil(result)
    }

    func testWhenMessageWithItemsPassesAndSomeItemsPassRules_ThenReturnMessage() throws {
        // GIVEN
        // Valid rule
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        // Invalid rule
        let rule2 = RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [OSMatchingAttribute(value: "nonexistent_os", fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [1]), // Will pass
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [2])  // Will fail
        ]
        let expectedItem = try XCTUnwrap(items.first)
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: [expectedItem])
        let remoteConfig = RemoteConfigModel(messages: [expectedMessage], rules: [rule1, rule2])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage)
    }

    func testWhenMessageWithItemsHasNoItemRules_ThenAllItemsPassAndReturnMessage() {
        // GIVEN
        let validRule = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: []), // No rules -> Will pass
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [])  // No rules -> Will pass
        ]
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)
        let remoteConfig = RemoteConfigModel(messages: [expectedMessage], rules: [validRule])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage)
    }

    func testWhenMessageWithItemsHasExclusionRules_ThenFilterItemsCorrectly() throws {
        // GIVEN
        let validRule = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [1]), // Will pass
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", exclusionRules: [1]) // Will be excluded (rule matches)
        ]
        let expectedItem = try XCTUnwrap(items.first)
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: [expectedItem])
        let remoteConfig = RemoteConfigModel(messages: [expectedMessage], rules: [validRule])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage)
    }

    func testWhenMessageFailsRules_ThenItemRulesNotEvaluated() {
        // GIVEN
        // Valid rule
        let validRule = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        // Invalid rule
        let invalidRule = RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [OSMatchingAttribute(value: "nonexistent_os", fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [1]),  // Would pass, but shouldn't be evaluated
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [1])   // Would pass, but shouldn't be evaluated
        ]

        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "1", matchingRules: [2], exclusionRules: [], items: items)], rules: [validRule, invalidRule])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertNil(result)
    }

    func testWhenMessageWithoutItems_ThenEvaluateNormally() {
        // GIVEN
        let validRule = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let expectedMessage = mediumMessage(matchingRules: [1], exclusionRules: [])
        let remoteConfig = RemoteConfigModel(messages: [expectedMessage], rules: [validRule])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage)
    }

    // MARK: - Item-Level Percentile Tests

    func testWhenMessagePassesButAllItemsFailPercentile_ThenReturnNull() {
        // GIVEN
        // Rule 1 50% of users
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: RemoteConfigTargetPercentile(before: 0.5), attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        // Rule 2 40% of users
        let rule2 = RemoteConfigRule(id: 2, targetPercentile: RemoteConfigTargetPercentile(before: 0.4), attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        // Rule 3 40% of users
        let rule3 = RemoteConfigRule(id: 3, targetPercentile: RemoteConfigTargetPercentile(before: 0.4), attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])

        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.percentileStorage = [
            "cards_message": 0.3,  // Message passes (≤ 0.5)
            "item1": 0.8,          // Item fails (> 0.4)
            "item2": 0.9           // Item fails (> 0.4)
        ]

        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [2]),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [3])
        ]
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "cards_message", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1, rule2, rule3])
        setupSUT(percentileStore: percentileStore)

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertNil(result, "Message should be nil when all items fail percentile checks")
    }

    func testWhenMessagePassesAndSomeItemsPassPercentile_ThenReturnMessageWithFilteredItems() throws {
        // GIVEN
        // Rule 1 50% of users
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: RemoteConfigTargetPercentile(before: 0.5), attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        // Rule 2 40% of users
        let rule2 = RemoteConfigRule(id: 2, targetPercentile: RemoteConfigTargetPercentile(before: 0.4), attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        // Rule 3 40% of users
        let rule3 = RemoteConfigRule(id: 3, targetPercentile: RemoteConfigTargetPercentile(before: 0.4), attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])

        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.percentileStorage = [
            "cards_message": 0.3,  // Message passes (≤ 0.5)
            "item1": 0.2,          // Item passes (≤ 0.4)
            "item2": 0.9           // Item fails (> 0.4)
        ]

        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [2]),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [3])
        ]
        let expectedItem = try XCTUnwrap(items.first)
        let expectedMessage = cardsListMessage(id: "cards_message", matchingRules: [1], exclusionRules: [], items: [expectedItem])
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "cards_message", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1, rule2, rule3])
        setupSUT(percentileStore: percentileStore)

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Should return message with only items that pass percentile")
    }

    func testWhenMessageFailsPercentile_ThenItemPercentileNotEvaluated() {
        // GIVEN
        // Rule 1 50% of users
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: RemoteConfigTargetPercentile(before: 0.5), attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        // Rule 2 40% of users
        let rule2 = RemoteConfigRule(id: 2, targetPercentile: RemoteConfigTargetPercentile(before: 0.4), attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        // Rule 3 40% of users
        let rule3 = RemoteConfigRule(id: 3, targetPercentile: RemoteConfigTargetPercentile(before: 0.4), attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])

        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.percentileStorage = [
            "cards_message": 0.8,  // Message fails (> 0.5)
            "item1": 0.1,          // Item would pass, but shouldn't be evaluated
            "item2": 0.2           // Item would pass, but shouldn't be evaluated
        ]

        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [2]),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [3])
        ]
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "cards_message", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1, rule2, rule3])
        setupSUT(percentileStore: percentileStore)

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertNil(result, "Should be nil because message fails percentile check (items never evaluated)")
    }

    func testWhenItemsHaveNoPercentileRules_ThenAllItemsPass() {
        // GIVEN
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: RemoteConfigTargetPercentile(before: 0.5), attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])

        let percentileStore = MockRemoteMessagePercentileStore()
        percentileStore.percentileStorage = [
            "cards_message": 0.3   // Only message has percentile rule
        ]

        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: []),    // No rules = auto-pass
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [])     // No rules = auto-pass
        ]
        let expectedMessage = cardsListMessage(id: "cards_message", matchingRules: [1], exclusionRules: [], items: items)
        let remoteConfig = RemoteConfigModel(messages: [expectedMessage], rules: [rule1])
        setupSUT(percentileStore: percentileStore)

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Should return message with all items when items have no percentile rules")
    }

    // MARK: - Section itemIDs Filtering Tests

    func testWhenSectionReferencesValidItems_ThenSectionIsKept() {
        // GIVEN
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Features", itemIDs: ["item1", "item2"]),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [1]),  // Will pass
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [1])   // Will pass
        ]
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)
        let remoteConfig = RemoteConfigModel(messages: [expectedMessage], rules: [rule1])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Section should be kept when all its itemIDs reference valid items")
    }

    func testWhenSectionReferencesSomeFilteredItems_ThenSectionIsKeptIfAtLeastOneItemExists() throws {
        // GIVEN
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let rule2 = RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [OSMatchingAttribute(value: "nonexistent_os", fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Features", itemIDs: ["item1", "item2"]),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [1]),  // Will pass
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [2])   // Will fail
        ]
        let expectedItems = [
            items[0],  // Section kept because item1 still exists
            items[1]   // item1 passes
        ]
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: expectedItems)
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1, rule2])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Section should be kept when at least one of its itemIDs still exists after filtering")
    }

    func testWhenSectionReferencesAllFilteredItems_ThenSectionIsRemoved() throws {
        // GIVEN
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let rule2 = RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [OSMatchingAttribute(value: "nonexistent_os", fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Features", itemIDs: ["item1", "item2"]),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [2]),  // Will fail
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [2]),  // Will fail
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item3", matchingRules: [1])   // Will pass
        ]
        let expectedItems = [items[3]]  // Only item3 remains
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: expectedItems)
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1, rule2])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Section should be removed when all its itemIDs have been filtered out")
    }

    func testWhenSectionReferencesNonExistentItems_ThenSectionIsRemoved() throws {
        // GIVEN
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Features", itemIDs: ["nonexistent1", "nonexistent2"]),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [1])   // Will pass
        ]
        let expectedItems = [items[1]]  // Only item1 remains
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: expectedItems)
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Section should be removed when its itemIDs reference items that don't exist")
    }

    func testWhenMultipleSectionsWithMixedValidInvalidItemIDs_ThenFilterCorrectly() throws {
        // GIVEN
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let rule2 = RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [OSMatchingAttribute(value: "nonexistent_os", fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Good Features", itemIDs: ["item1"]),  // Will be kept
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [1]),  // Will pass
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section2", titleText: "Bad Features", itemIDs: ["item2"]),   // Will be removed because item 2 will be removed
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [2]),  // Will fail
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section3", titleText: "More Features", itemIDs: ["item3"]), // Will be kept
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item3", matchingRules: [1])   // Will pass
        ]
        let expectedItems = [
            items[0],  // section1 kept
            items[1],  // item1 passes
            items[4],  // section3 kept
            items[5]   // item3 passes
        ]
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: expectedItems)
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1, rule2])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Should keep sections whose itemIDs exist and remove sections whose itemIDs don't exist")
    }

    func testWhenMessageContainsOnlySections_ThenReturnNil() {
        // GIVEN
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Features", itemIDs: ["item1"]),
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section2", titleText: "Improvements", itemIDs: ["item2"])
        ]
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertNil(result, "Message with only sections (no actual items) should return nil")
    }

    // MARK: - Featured Item Section Reference Tests

    func testWhenSectionReferencesOnlyFeaturedItems_AndFeaturedItemIsFiltered_ThenSectionIsRemoved() throws {
        // GIVEN - Section references featured item that gets filtered out
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let rule2 = RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [OSMatchingAttribute(value: "nonexistent_os", fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Featured Section", itemIDs: ["featured1"]),
            RemoteMessageModelType.ListItem.makeFeaturedItem(id: "featured1", titleText: "Featured Feature", matchingRules: [2]),  // Will be filtered
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [1])   // Will pass
        ]
        let expectedItems = [items[2]]  // Only item1 remains
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: expectedItems)
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1, rule2])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Section should be removed when the featured item it references is filtered out")
    }

    func testWhenSectionReferencesOnlyFeaturedItem_ThenSectionIsRemoved() throws {
        // GIVEN - Section that only references a featured item should be removed
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Featured Section", itemIDs: ["featured1"]),
            RemoteMessageModelType.ListItem.makeFeaturedItem(id: "featured1", titleText: "Featured Feature", matchingRules: []),  // Featured item
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [])   // Regular item
        ]
        let expectedItems = [
            items[1],  // featured1 (kept, not filtered)
            items[2]   // item1 (kept)
        ]
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [], exclusionRules: [], items: expectedItems)
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "1", matchingRules: [], exclusionRules: [], items: items)], rules: [])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Section should be removed when it only references featured items")
    }

    func testWhenSectionReferencesBothFeaturedAndRegularItems_ThenSectionIsKeptWithOnlyRegularItemReference() throws {
        // GIVEN - Section references both featured and regular items, only regular item should count
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Mixed Section", itemIDs: ["featured1", "item1"]),
            RemoteMessageModelType.ListItem.makeFeaturedItem(id: "featured1", titleText: "Featured Feature", matchingRules: [1]),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [1])
        ]
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)
        let remoteConfig = RemoteConfigModel(messages: [expectedMessage], rules: [rule1])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Section should be kept when at least one regular (non-featured) item exists")
    }

    func testWhenSectionReferencesMixOfFeaturedAndRegularItems_AndRegularItemsFiltered_ThenSectionIsRemoved() throws {
        // GIVEN - Section references both featured and regular items, but regular items are filtered
        let rule1 = RemoteConfigRule(id: 1, targetPercentile: nil, attributes: [OSMatchingAttribute(value: AppVersion.shared.osVersionMajorMinorPatch, fallback: nil)])
        let rule2 = RemoteConfigRule(id: 2, targetPercentile: nil, attributes: [OSMatchingAttribute(value: "nonexistent_os", fallback: nil)])
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Mixed Section", itemIDs: ["featured1", "item1"]),
            RemoteMessageModelType.ListItem.makeFeaturedItem(id: "featured1", titleText: "Featured Feature", matchingRules: [1]),  // Will pass
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", matchingRules: [2]),   // Will be filtered
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", matchingRules: [1])    // Will pass (not in section)
        ]
        let expectedItems = [
            items[1],  // featured1
            items[3]   // item2
        ]
        let expectedMessage = cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: expectedItems)
        let remoteConfig = RemoteConfigModel(messages: [cardsListMessage(id: "1", matchingRules: [1], exclusionRules: [], items: items)], rules: [rule1, rule2])

        // WHEN
        let result = matcher.evaluate(remoteConfig: remoteConfig)

        // THEN
        XCTAssertEqual(result, expectedMessage, "Section should be removed when only featured items remain in its itemIDs after filtering")
    }

}

private extension RemoteMessagingConfigMatcherTests {

    func setupSUT(percentileStore: MockRemoteMessagePercentileStore = MockRemoteMessagePercentileStore()) {
        matcher = RemoteMessagingConfigMatcher(
            appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
            userAttributeMatcher: MobileUserAttributeMatcher(
                statisticsStore: MockStatisticsStore(),
                featureDiscovery: MockFeatureDiscovery(),
                variantManager: MockVariantManager(),
                bookmarksCount: 0,
                favoritesCount: 0,
                appTheme: "light",
                isWidgetInstalled: false,
                daysSinceNetPEnabled: -1,
                isSubscriptionEligibleUser: false,
                isDuckDuckGoSubscriber: false,
                subscriptionDaysSinceSubscribed: -1,
                subscriptionDaysUntilExpiry: -1,
                subscriptionPurchasePlatform: nil,
                isSubscriptionActive: false,
                isSubscriptionExpiring: false,
                isSubscriptionExpired: false,
                subscriptionFreeTrialActive: false,
                isDuckPlayerOnboarded: false,
                isDuckPlayerEnabled: false,
                dismissedMessageIds: [],
                shownMessageIds: [],
                enabledFeatureFlags: [],
                isSyncEnabled: false,
                shouldShowWinBackOfferUrgencyMessage: false,
                isCurrentPIRUser: false
            ),
            percentileStore: percentileStore,
            surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
            dismissedMessageIds: []
        )
    }

    func mediumMessage(id: String = "1", matchingRules: [Int], exclusionRules: [Int]) -> RemoteMessageModel {
        return RemoteMessageModel(id: id,
                                  surfaces: .newTabPage,
                                  content: .medium(titleText: "title", descriptionText: "description", placeholder: .announce),
                                  matchingRules: matchingRules,
                                  exclusionRules: exclusionRules,
                                  isMetricsEnabled: true
        )
    }

    func cardsListMessage(id: String = "1", matchingRules: [Int], exclusionRules: [Int], items: [RemoteMessageModelType.ListItem]) -> RemoteMessageModel {
        return RemoteMessageModel(id: id,
                                  surfaces: [.modal, .dedicatedTab],
                                  content: .cardsList(titleText: "Feature List", placeholder: nil, items: items, primaryActionText: "Got It", primaryAction: .dismiss),
                                  matchingRules: matchingRules,
                                  exclusionRules: exclusionRules,
                                  isMetricsEnabled: true
        )
    }

}
