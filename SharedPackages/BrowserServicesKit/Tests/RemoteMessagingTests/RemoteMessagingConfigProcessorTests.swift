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

        let remoteMessagingConfigMatcher = makeBasicConfigMatcher()

        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)
        let config: RemoteMessagingConfig = RemoteMessagingConfig(version: jsonRemoteMessagingConfig.version - 1,
                                                                  invalidate: false,
                                                                  evaluationTimestamp: Date())

        let processorResult = processor.process(jsonRemoteMessagingConfig: jsonRemoteMessagingConfig, currentConfig: config, supportedSurfacesForMessage: { _ in .newTabPage })
        XCTAssertNotNil(processorResult)
        XCTAssertEqual(processorResult?.version, jsonRemoteMessagingConfig.version)
        XCTAssertNotNil(processorResult?.message)
    }

    func testWhenSameVersionThenNotProcessedAndResultNil() throws {
        let jsonRemoteMessagingConfig = try decodeJson(fileName: "remote-messaging-config-malformed.json")
        XCTAssertNotNil(jsonRemoteMessagingConfig)

        let remoteMessagingConfigMatcher = makeBasicConfigMatcher()

        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)
        let config: RemoteMessagingConfig = RemoteMessagingConfig(version: jsonRemoteMessagingConfig.version,
                                                                  invalidate: false,
                                                                  evaluationTimestamp: Date())

        let result = processor.process(jsonRemoteMessagingConfig: jsonRemoteMessagingConfig, currentConfig: config, supportedSurfacesForMessage: { _ in .newTabPage })
        XCTAssertNil(result)
    }

    func decodeJson(fileName: String) throws -> RemoteMessageResponse.JsonRemoteMessagingConfig {
        let resourceURL = Bundle.module.resourceURL!.appendingPathComponent(fileName, conformingTo: .json)
        let validJson = try Data(contentsOf: resourceURL)
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        XCTAssertNotNil(remoteMessagingConfig)

        return remoteMessagingConfig
    }

    // MARK: - Featured Item Reordering Tests

    func testWhenFeaturedItemIsInFirstPositionThenOrderRemainsUnchanged() throws {
        // GIVEN
        let jsonConfig = try decodeJson(fileName: "remote-messaging-config-featured-items.json")
        let remoteMessagingConfigMatcher = makeBasicConfigMatcher()
        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)

        // Find the message with featured item in first position
        let messageConfig = jsonConfig.messages.first { $0.id == "featured_item_first_position" }
        XCTAssertNotNil(messageConfig)

        // WHEN
        let result = processor.process(
            jsonRemoteMessagingConfig: jsonConfig,
            currentConfig: nil,
            supportedSurfacesForMessage: { _ in .modal }
        )

        // THEN
        let items = try XCTUnwrap(result?.message?.content?.listItems)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].id, "featured-1")
        XCTAssertEqual(items[1].id, "item-1")
        XCTAssertEqual(items[2].id, "item-2")
    }

    func testWhenFeaturedItemIsInMiddlePositionThenMoveItToFirstPosition() throws {
        // GIVEN - Create a JSON config with only the middle position message
        let jsonConfig = try decodeJson(fileName: "remote-messaging-config-featured-items.json")
        let middlePositionMessage = try XCTUnwrap(jsonConfig.messages.first { $0.id == "featured_item_middle_position" })

        let singleMessageConfig = RemoteMessageResponse.JsonRemoteMessagingConfig(
            version: jsonConfig.version,
            messages: [middlePositionMessage],
            rules: jsonConfig.rules
        )

        let remoteMessagingConfigMatcher = makeBasicConfigMatcher()
        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)

        // WHEN
        let result = processor.process(
            jsonRemoteMessagingConfig: singleMessageConfig,
            currentConfig: nil,
            supportedSurfacesForMessage: { _ in .modal }
        )

        // THEN
        let items = try XCTUnwrap(result?.message?.content?.listItems)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].id, "featured-1")
        XCTAssertEqual(items[1].id, "item-1")
        XCTAssertEqual(items[2].id, "item-2")
    }

    func testWhenFeaturedItemIsInLastPositionThenMoveItToFirstPosition() throws {
        // GIVEN
        let jsonConfig = try decodeJson(fileName: "remote-messaging-config-featured-items.json")
        let lastPositionMessage = try XCTUnwrap(jsonConfig.messages.first { $0.id == "featured_item_last_position" })

        let singleMessageConfig = RemoteMessageResponse.JsonRemoteMessagingConfig(
            version: jsonConfig.version,
            messages: [lastPositionMessage],
            rules: jsonConfig.rules
        )

        let remoteMessagingConfigMatcher = makeBasicConfigMatcher()
        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)

        // WHEN
        let result = processor.process(
            jsonRemoteMessagingConfig: singleMessageConfig,
            currentConfig: nil,
            supportedSurfacesForMessage: { _ in .modal }
        )

        // THEN
        let items = try XCTUnwrap(result?.message?.content?.listItems)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].id, "featured-1")
        XCTAssertEqual(items[1].id, "item-1")
        XCTAssertEqual(items[2].id, "item-2")
    }

    func testWhenMessageHasNoFeaturedItemThenOrderRemainsUnchanged() throws {
        // GIVEN
        let jsonConfig = try decodeJson(fileName: "remote-messaging-config-featured-items.json")
        let noFeaturedMessage = try XCTUnwrap(jsonConfig.messages.first { $0.id == "no_featured_item" })

        let singleMessageConfig = RemoteMessageResponse.JsonRemoteMessagingConfig(
            version: jsonConfig.version,
            messages: [noFeaturedMessage],
            rules: jsonConfig.rules
        )

        let remoteMessagingConfigMatcher = makeBasicConfigMatcher()
        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)

        // WHEN
        let result = processor.process(
            jsonRemoteMessagingConfig: singleMessageConfig,
            currentConfig: nil,
            supportedSurfacesForMessage: { _ in .modal }
        )

        // THEN
        let items = try XCTUnwrap(result?.message?.content?.listItems)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].id, "item-1")
        XCTAssertEqual(items[1].id, "item-2")
        XCTAssertEqual(items[2].id, "item-3")
    }

    func testWhenMessageIsNotCardsListThenReturnsUnchanged() throws {
        // GIVEN - Use the existing config that has non-cardsList messages
        let jsonConfig = try decodeJson(fileName: "remote-messaging-config.json")

        let remoteMessagingConfigMatcher = makeBasicConfigMatcher()
        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)

        // WHEN
        let result = processor.process(
            jsonRemoteMessagingConfig: jsonConfig,
            currentConfig: nil,
            supportedSurfacesForMessage: { _ in .newTabPage }
        )

        // THEN - Verify it returns a non-cardsList message type
        XCTAssertNotNil(result?.message)
        if case .cardsList = result?.message?.content {
            XCTFail("Expected non-cardsList message type")
        }
    }

    func testWhenFeaturedItemWithSectionsThenMoveItToFirstPosition() throws {
        // GIVEN
        let jsonConfig = try decodeJson(fileName: "remote-messaging-config-featured-items.json")
        let withSectionsMessage = try XCTUnwrap(jsonConfig.messages.first { $0.id == "featured_item_with_sections" })

        let singleMessageConfig = RemoteMessageResponse.JsonRemoteMessagingConfig(
            version: jsonConfig.version,
            messages: [withSectionsMessage],
            rules: jsonConfig.rules
        )

        let remoteMessagingConfigMatcher = makeBasicConfigMatcher()
        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)

        // WHEN
        let result = processor.process(
            jsonRemoteMessagingConfig: singleMessageConfig,
            currentConfig: nil,
            supportedSurfacesForMessage: { _ in .modal }
        )

        // THEN
        let items = try XCTUnwrap(result?.message?.content?.listItems)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0].id, "featured-1")
        XCTAssertEqual(items[1].id, "item-1")
        XCTAssertEqual(items[2].id, "item-2")
        XCTAssertEqual(items[3].id, "section-1")
    }

}

// MARK: - Helpers

private extension RemoteMessagingConfigProcessorTests {

    func makeBasicConfigMatcher() -> RemoteMessagingConfigMatcher {
        return RemoteMessagingConfigMatcher(
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
            percentileStore: MockRemoteMessagePercentileStore(),
            surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
            dismissedMessageIds: []
        )
    }
}
