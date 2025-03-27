//
//  RemoteMessagingConfigProcessorTests.swift
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

import BrowserServicesKitTestsUtils
import RemoteMessagingTestsUtils
import XCTest
@testable import RemoteMessaging

class RemoteMessagingConfigProcessorTests: XCTestCase {

    func testWhenNewVersionThenShouldHaveBeenProcessedAndResultReturned() throws {
        let jsonRemoteMessagingConfig = try decodeJson(fileName: "remote-messaging-config.json")
        XCTAssertNotNil(jsonRemoteMessagingConfig)

        let remoteMessagingConfigMatcher = RemoteMessagingConfigMatcher(
            appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
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
                shownMessageIds: []
            ),
            percentileStore: MockRemoteMessagePercentileStore(),
            surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
            dismissedMessageIds: []
        )

        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)
        let config: RemoteMessagingConfig = RemoteMessagingConfig(version: jsonRemoteMessagingConfig.version - 1,
                                                                  invalidate: false,
                                                                  evaluationTimestamp: Date())

        let processorResult = processor.process(jsonRemoteMessagingConfig: jsonRemoteMessagingConfig, currentConfig: config)
        XCTAssertNotNil(processorResult)
        XCTAssertEqual(processorResult?.version, jsonRemoteMessagingConfig.version)
        XCTAssertNotNil(processorResult?.message)
    }

    func testWhenSameVersionThenNotProcessedAndResultNil() throws {
        let jsonRemoteMessagingConfig = try decodeJson(fileName: "remote-messaging-config-malformed.json")
        XCTAssertNotNil(jsonRemoteMessagingConfig)

        let remoteMessagingConfigMatcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
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
                    shownMessageIds: []
                ),
                percentileStore: MockRemoteMessagePercentileStore(),
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: [])

        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)
        let config: RemoteMessagingConfig = RemoteMessagingConfig(version: jsonRemoteMessagingConfig.version,
                                                                  invalidate: false,
                                                                  evaluationTimestamp: Date())

        let result = processor.process(jsonRemoteMessagingConfig: jsonRemoteMessagingConfig, currentConfig: config)
        XCTAssertNil(result)
    }

    func decodeJson(fileName: String) throws -> RemoteMessageResponse.JsonRemoteMessagingConfig {
        let resourceURL = Bundle.module.resourceURL!.appendingPathComponent(fileName, conformingTo: .json)
        let validJson = try Data(contentsOf: resourceURL)
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        XCTAssertNotNil(remoteMessagingConfig)

        return remoteMessagingConfig
    }
}
