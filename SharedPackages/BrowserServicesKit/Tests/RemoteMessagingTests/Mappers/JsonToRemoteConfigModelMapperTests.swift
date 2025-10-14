//
//  JsonToRemoteConfigModelMapperTests.swift
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

import XCTest
import RemoteMessagingTestsUtils
@testable import RemoteMessaging

class JsonToRemoteConfigModelMapperTests: XCTestCase {

    func testWhenValidJsonParsedThenMessagesMappedIntoRemoteConfig() throws {
        let config = try decodeAndMapJson(fileName: "remote-messaging-config.json")
        XCTAssertEqual(config.messages.count, 8)

        XCTAssertEqual(config.messages[0], RemoteMessageModel(
                id: "8274589c-8aeb-4322-a737-3852911569e3",
                content: .bigSingleAction(titleText: "title", descriptionText: "description", placeholder: .announce,
                                          primaryActionText: "Ok", primaryAction: .url(value: "https://duckduckgo.com")),
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true)
        )

        XCTAssertEqual(config.messages[1], RemoteMessageModel(
                id: "8274589c-8aeb-4322-a737-3852911569e3",
                content: .bigSingleAction(titleText: "Kedvenc hozzáadása", descriptionText: "Kedvenc eltávolítása", placeholder: .ddgAnnounce,
                                          primaryActionText: "Ok", primaryAction: .url(value: "https://duckduckgo.com")),
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true)
        )

        XCTAssertEqual(config.messages[2], RemoteMessageModel(
                id: "26780792-49fe-4e25-ae27-aa6a2e6f013b",
                content: .small(titleText: "Here goes a title", descriptionText: "description"),
                matchingRules: [5, 6],
                exclusionRules: [7, 8, 9],
                isMetricsEnabled: true)
        )

        XCTAssertEqual(config.messages[3], RemoteMessageModel(
                id: "c3549d64-b388-41d8-9649-33e6e2674e8e",
                content: .medium(titleText: "Here goes a title", descriptionText: "description", placeholder: .criticalUpdate),
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true)
        )

        XCTAssertEqual(config.messages[4], RemoteMessageModel(
                id: "c2d0a1f1-6157-434f-8145-38416037d339",
                content: .bigTwoAction(titleText: "Here goes a title", descriptionText: "description", placeholder: .appUpdate,
                                       primaryActionText: "Ok", primaryAction: .appStore,
                                       secondaryActionText: "Cancel", secondaryAction: .dismiss),
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true)
        )

        XCTAssertEqual(config.messages[5], RemoteMessageModel(
            id: "96EEA91B-030D-41E5-95A7-F11C1952A5FF",
            content: .bigTwoAction(titleText: "Here goes a title", descriptionText: "description", placeholder: .newForMacAndWindows,
                                   primaryActionText: "Ok", primaryAction: .share(value: "https://duckduckgo.com/app",
                                                                                  title: "Share Title"),
                                   secondaryActionText: "Cancel", secondaryAction: .dismiss),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: true)
        )

        XCTAssertEqual(config.messages[6], RemoteMessageModel(
            id: "6E58D3DA-AB9D-47A4-87B7-B8AF830BFB5E",
            content: .promoSingleAction(titleText: "Promo Title", descriptionText: "Promo Description", placeholder: .newForMacAndWindows,
                                        actionText: "Promo Action", action: .dismiss),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: true)
        )

        XCTAssertEqual(config.messages[7], RemoteMessageModel(
            id: "8E909844-C809-4543-AAFE-2C75DC285B3B",
            content: .promoSingleAction(
                titleText: "Survey Title",
                descriptionText: "Survey Description",
                placeholder: .privacyShield,
                actionText: "Survey Action",
                action: .survey(value: "https://duckduckgo.com/survey")
            ),
            matchingRules: [8],
            exclusionRules: [],
            isMetricsEnabled: true)
        )

    }

    func testWhenValidJsonParsedThenRulesMappedIntoRemoteConfig() throws {
        let config = try decodeAndMapJson(fileName: "remote-messaging-config.json")
        XCTAssertTrue(config.rules.count == 7)

        let rule5 = config.rules.filter { $0.id == 5 }.first
        XCTAssertNotNil(rule5)
        XCTAssertNil(rule5?.targetPercentile)
        XCTAssertTrue(rule5?.attributes.count == 16)
        var attribs = rule5?.attributes.filter { $0 is LocaleMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? LocaleMatchingAttribute, LocaleMatchingAttribute(value: ["en-US", "en-GB"], fallback: true))

        let rule6 = config.rules.filter { $0.id == 6 }.first
        XCTAssertNotNil(rule6)
        XCTAssertNil(rule6?.targetPercentile)
        XCTAssertTrue(rule6?.attributes.count == 1)
        attribs = rule6?.attributes.filter { $0 is LocaleMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? LocaleMatchingAttribute, LocaleMatchingAttribute(value: ["en-GB"], fallback: nil))

        let rule7 = config.rules.filter { $0.id == 7 }.first
        XCTAssertNotNil(rule7)
        XCTAssertNil(rule7?.targetPercentile)
        XCTAssertTrue(rule7?.attributes.count == 1)
        attribs = rule7?.attributes.filter { $0 is WidgetAddedMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? WidgetAddedMatchingAttribute, WidgetAddedMatchingAttribute(value: false, fallback: nil))

        let rule8 = config.rules.filter { $0.id == 8 }.first
        XCTAssertNotNil(rule8)
        XCTAssertNil(rule8?.targetPercentile)
        XCTAssertTrue(rule8?.attributes.count == 7)

        attribs = rule8?.attributes.filter { $0 is DaysSinceNetPEnabledMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? DaysSinceNetPEnabledMatchingAttribute, DaysSinceNetPEnabledMatchingAttribute(min: 5, fallback: nil))

        attribs = rule8?.attributes.filter { $0 is IsSubscriptionEligibleUserMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(
            attribs?.first as? IsSubscriptionEligibleUserMatchingAttribute,
            IsSubscriptionEligibleUserMatchingAttribute(value: true, fallback: nil)
        )

        attribs = rule8?.attributes.filter { $0 is IsDuckDuckGoSubscriberUserMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(
            attribs?.first as? IsDuckDuckGoSubscriberUserMatchingAttribute,
            IsDuckDuckGoSubscriberUserMatchingAttribute(value: true, fallback: nil)
        )

        attribs = rule8?.attributes.filter { $0 is SubscriptionDaysSinceSubscribedMatchingAttribute }
        XCTAssertEqual(attribs?.first as? SubscriptionDaysSinceSubscribedMatchingAttribute, SubscriptionDaysSinceSubscribedMatchingAttribute(
            min: 5, max: 8, fallback: nil
        ))

        attribs = rule8?.attributes.filter { $0 is SubscriptionDaysUntilExpiryMatchingAttribute }
        XCTAssertEqual(attribs?.first as? SubscriptionDaysUntilExpiryMatchingAttribute, SubscriptionDaysUntilExpiryMatchingAttribute(
            min: 25, max: 30, fallback: nil
        ))

        attribs = rule8?.attributes.filter { $0 is SubscriptionPurchasePlatformMatchingAttribute }
        XCTAssertEqual(attribs?.first as? SubscriptionPurchasePlatformMatchingAttribute, SubscriptionPurchasePlatformMatchingAttribute(
            value: ["apple", "stripe"], fallback: nil
        ))

        attribs = rule8?.attributes.filter { $0 is SubscriptionStatusMatchingAttribute }
        XCTAssertEqual(attribs?.first as? SubscriptionStatusMatchingAttribute, SubscriptionStatusMatchingAttribute(
            value: ["active", "expiring"], fallback: nil
        ))

        let rule9 = config.rules.filter { $0.id == 9 }.first
        XCTAssertNotNil(rule9)
        XCTAssertNotNil(rule9?.targetPercentile)
        XCTAssertTrue(rule9?.attributes.count == 1)
        XCTAssertEqual(rule9?.targetPercentile?.before, 0.9)

        let rule10 = config.rules.filter { $0.id == 10 }.first
        XCTAssertNotNil(rule10)
        XCTAssertNil(rule10?.targetPercentile)
        XCTAssertTrue(rule10?.attributes.count == 1)

        attribs = rule10?.attributes.filter { $0 is InteractedWithMessageMatchingAttribute }
        XCTAssertEqual(attribs?.first as? InteractedWithMessageMatchingAttribute, InteractedWithMessageMatchingAttribute(value: ["One", "Two"], fallback: nil))

        let rule11 = config.rules.filter { $0.id == 11 }.first
        XCTAssertNotNil(rule11)
        XCTAssertNil(rule11?.targetPercentile)
        XCTAssertTrue(rule11?.attributes.count == 1)

        attribs = rule11?.attributes.filter { $0 is SyncEnabledMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? SyncEnabledMatchingAttribute, SyncEnabledMatchingAttribute(value: true, fallback: nil))

    }

    func testWhenJsonMessagesHaveUnknownTypesThenMessagesNotMappedIntoConfig() throws {
        let config = try decodeAndMapJson(fileName: "remote-messaging-config-unsupported-items.json")
        let countValidContent = config.messages.filter { $0.content != nil }.count
        XCTAssertEqual(countValidContent, 1)
    }

    func testWhenJsonMessagesHaveUnknownTypesThenRulesMappedIntoConfig() throws {
        let config = try decodeAndMapJson(fileName: "remote-messaging-config-unsupported-items.json")
        XCTAssertTrue(config.rules.count == 2)

        let rule6 = config.rules.filter { $0.id == 6 }.first
        XCTAssertNotNil(rule6)
        var attribs = rule6?.attributes.filter { $0 is UnknownMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? UnknownMatchingAttribute, UnknownMatchingAttribute(fallback: true))

        let rule7 = config.rules.filter { $0.id == 7 }.first
        XCTAssertNotNil(rule7)
        attribs = rule7?.attributes.filter { $0 is WidgetAddedMatchingAttribute }
        XCTAssertEqual(attribs?.count, 1)
        XCTAssertEqual(attribs?.first as? WidgetAddedMatchingAttribute, WidgetAddedMatchingAttribute(value: true, fallback: nil))
    }

    func testWhenJsonAttributeMissingThenUnknownIntoConfig() throws {
        let resourceURL = Bundle.module.resourceURL!.appendingPathComponent("remote-messaging-config-malformed.json", conformingTo: .json)
        let validJson = try Data(contentsOf: resourceURL)

        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        let surveyMapper = MockRemoteMessageSurveyActionMapper()
        XCTAssertNotNil(remoteMessagingConfig)
        let config = JsonToRemoteConfigModelMapper.mapJson(remoteMessagingConfig: remoteMessagingConfig, surveyActionMapper: surveyMapper)
        XCTAssertTrue(config.rules.count == 2)

        let rule6 = config.rules.filter { $0.id == 6 }.first
        XCTAssertNotNil(rule6)
        XCTAssertEqual(rule6?.attributes.filter { $0 is LocaleMatchingAttribute }.count, 1)
        XCTAssertEqual(rule6?.attributes.filter { $0 is OSMatchingAttribute }.count, 1)
        XCTAssertEqual(rule6?.attributes.filter { $0 is UnknownMatchingAttribute }.count, 1)
    }

    func testThatMetricsAreEnabledWhenStatedInJSONOrMissing() throws {
        let config = try decodeAndMapJson(fileName: "remote-messaging-config-metrics.json")
        XCTAssertEqual(config.messages.count, 4)

        XCTAssertEqual(config.messages[0], RemoteMessageModel(
                id: "1",
                content: .small(titleText: "title", descriptionText: "description"),
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true)
        )

        XCTAssertEqual(config.messages[1], RemoteMessageModel(
                id: "2",
                content: .small(titleText: "title", descriptionText: "description"),
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true)
        )

        XCTAssertEqual(config.messages[2], RemoteMessageModel(
                id: "3",
                content: .small(titleText: "title", descriptionText: "description"),
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: false)
        )

        XCTAssertEqual(config.messages[3], RemoteMessageModel(
                id: "4",
                content: .small(titleText: "title", descriptionText: "description"),
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true)
        )
    }

    func decodeAndMapJson(fileName: String) throws -> RemoteConfigModel {
        let resourceURL = Bundle.module.resourceURL!.appendingPathComponent(fileName, conformingTo: .json)
        let validJson = try Data(contentsOf: resourceURL)
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        let surveyMapper = MockRemoteMessageSurveyActionMapper()
        XCTAssertNotNil(remoteMessagingConfig)

        let config = JsonToRemoteConfigModelMapper.mapJson(remoteMessagingConfig: remoteMessagingConfig, surveyActionMapper: surveyMapper)
        XCTAssertNotNil(config)
        return config
    }
}
