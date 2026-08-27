//
//  AIChatPixelMetricHandlerTests.swift
//  DuckDuckGoTests
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import Core
@testable import DuckDuckGo
import AIChat
@_spi(Testing) import PixelKit

final class AIChatPixelMetricHandlerTests: XCTestCase {

    private var handler: AIChatPixelMetricHandler!
    private var pixelKitMock: PixelKitMock!

    override func setUp() {
        super.setUp()
        pixelKitMock = PixelKitMock()
    }

    override func tearDown() {
        handler = nil
        pixelKitMock = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationWithTimeElapsed() {
        // Given
        let timeElapsed = 5

        // When
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: pixelKitMock)

        // Then
        XCTAssertNotNil(handler)
    }

    func testInitializationWithNilTimeElapsed() {
        // When
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: pixelKitMock)

        // Then
        XCTAssertNotNil(handler)
    }

    // MARK: - fireOpenAIChat Tests

    func testFireOpenAIChatWithoutTimeElapsed() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: pixelKitMock)

        // When
        handler.fireOpenAIChat()

        // Then
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.aiChatOpen.name)
        XCTAssertTrue(pixelKitMock.actualFireCalls.last?.additionalParameters?.isEmpty ?? false)
    }

    func testFireOpenAIChatWithTimeElapsed() {
        // Given
        let timeElapsed = 10
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: pixelKitMock)

        // When
        handler.fireOpenAIChat()

        // Then
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.aiChatOpen.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["delta-timestamp-minutes"], "10")
    }

    func testFireOpenAIChatWithZeroTimeElapsed() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: 0, pixelFiring: pixelKitMock)

        // When
        handler.fireOpenAIChat()

        // Then
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.aiChatOpen.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["delta-timestamp-minutes"], "0")
    }

    // MARK: - firePixelWithMetric Tests

    func testFirePixelWithMetricForKnownMetric() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: pixelKitMock)
        let metric = AIChatMetric(metricName: .userDidSubmitPrompt)

        // When
        handler.firePixelWithMetric(metric)

        // Then
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.aiChatMetricSentPromptOngoingChat.name)
        XCTAssertTrue(pixelKitMock.actualFireCalls.last?.additionalParameters?.isEmpty ?? false)
    }

    func testFirePixelWithMetricForKnownMetricWithTimeElapsed() {
        // Given
        let timeElapsed = 15
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: pixelKitMock)
        let metric = AIChatMetric(metricName: .userDidSubmitFirstPrompt)

        // When
        handler.firePixelWithMetric(metric)

        // Then
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.aiChatMetricStartNewConversation.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["delta-timestamp-minutes"], "15")
    }

    func testFirePixelWithMetricForAllKnownMetrics() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: pixelKitMock)
        let testCases: [(AIChatMetricName, Pixel.Event)] = [
            (.userDidSubmitPrompt, .aiChatMetricSentPromptOngoingChat),
            (.userDidSubmitFirstPrompt, .aiChatMetricStartNewConversation),
            (.userDidOpenHistory, .aiChatMetricOpenHistory),
            (.userDidSelectFirstHistoryItem, .aiChatMetricOpenMostRecentHistoryChat),
            (.userDidCreateNewChat, .aiChatMetricStartNewConversationButtonClicked),
            (.userDidTapKeyboardReturnKey, .aiChatMetricDuckAIKeyboardReturnPressed)
        ]

        // When & Then
        for (index, testCase) in testCases.enumerated() {
            let metric = AIChatMetric(metricName: testCase.0)
            handler.firePixelWithMetric(metric)

            XCTAssertEqual(pixelKitMock.actualFireCalls.count, index + 1)
            XCTAssertEqual(pixelKitMock.actualFireCalls[index].pixel.name, testCase.1.name)
        }
    }

    func testFirePixelWithMetricForKeyboardReturnKey() {
        // Given
        let timeElapsed = 15
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: pixelKitMock)
        let metric = AIChatMetric(metricName: .userDidTapKeyboardReturnKey)

        // When
        handler.firePixelWithMetric(metric)

        // Then
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.aiChatMetricDuckAIKeyboardReturnPressed.name)
        XCTAssertTrue(pixelKitMock.actualFireCalls.last?.additionalParameters?.isEmpty ?? false)
    }

    func testFirePixelWithMetricForUnknownMetricDoesNothing() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: pixelKitMock)

        // When - a metric name in neither the engagement nor the funnel table
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidAcceptTermsAndConditions))

        // Then
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
    }

    // MARK: - Subscription Funnel Map Tests

    /// No metric may be mapped twice: a funnel metric added to the engagement table would fire the wrong
    /// pixel, and a metric in both tables would be a latent double-count.
    func testEngagementAndFunnelTablesHaveDisjointKeys() {
        let engagementKeys = Set(AIChatPixelMetricHandler.metricToEventMap.keys)
        let funnelKeys = Set(AIChatPixelMetricHandler.funnelMetricToPixelMap.keys)

        XCTAssertTrue(engagementKeys.isDisjoint(with: funnelKeys),
                      "Overlapping keys: \(engagementKeys.intersection(funnelKeys))")
    }

    func testFunnelMapDeliberatelyOmitsFreePlanBadgeMetrics() {
        let funnelKeys = Set(AIChatPixelMetricHandler.funnelMetricToPixelMap.keys)

        XCTAssertFalse(funnelKeys.contains(.userDidViewFreePlanBadge))
        XCTAssertFalse(funnelKeys.contains(.userDidClickFreePlanUpgradeButton))
    }

    func testFirePixelWithMetricForFunnelMetricsFiresPairWithOrigin() {
        // Given
        let testCases: [(origin: String, view: AIChatMetricName, click: AIChatMetricName)] = [
            ("funnel_duckai_ios__aisidebar", .userDidViewAiSidebarUpgradeButton, .userDidClickAiSidebarUpgradeButton),
            ("funnel_duckai_ios__activatesubscription", .userDidViewActivateSubscriptionBanner, .userDidClickActivateSubscriptionButton),
            ("funnel_duckai_ios__freelimit", .userDidViewFreeLimitMessage, .userDidClickFreeLimitSubscribeLink),
            ("funnel_duckai_ios__imagegenerationlimit", .userDidViewImageGenerationLimitMessage, .userDidClickImageGenerationLimitSubscribeButton),
            ("funnel_duckai_ios__pluslimit", .userDidViewPlusLimitMessage, .userDidClickPlusLimitUpgradeLink),
            ("funnel_duckai_ios__promotioncard", .userDidViewPromotionCard, .userDidClickPromotionCardButton),
            ("funnel_duckai_ios__settings", .userDidViewSettingsSubscribeButton, .userDidClickSettingsSubscribeButton),
            ("funnel_duckai_ios__disclaimerbanner", .userDidViewProUpgradeDisclaimerBanner, .userDidClickProUpgradeDisclaimerBannerButton),
            ("funnel_duckai_ios__voicechatlimit", .userDidViewVoiceChatLimitModal, .userDidClickVoiceChatLimitModalSubscribeButton),
            ("funnel_duckai_ios__voicechatdurationlimit", .userDidViewVoiceChatDurationLimitModal, .userDidClickVoiceChatDurationLimitModalSubscribeButton)
        ]
        XCTAssertEqual(testCases.count * 2, AIChatPixelMetricHandler.funnelMetricToPixelMap.count,
                       "The funnel table gained or lost entries this test does not cover")

        // A non-nil elapsed time proves the funnel branch does not inherit the engagement branch's timestamp
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: 7, pixelFiring: pixelKitMock)

        for testCase in testCases {
            // When
            let countBeforeView = pixelKitMock.actualFireCalls.count
            handler.firePixelWithMetric(AIChatMetric(metricName: testCase.view))

            // Then
            XCTAssertEqual(pixelKitMock.actualFireCalls.count, countBeforeView + 1, "\(testCase.origin) view")
            XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.aiChatSubscriptionFunnelImpression.name)
            XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, ["origin": testCase.origin])

            // When
            let countBeforeClick = pixelKitMock.actualFireCalls.count
            handler.firePixelWithMetric(AIChatMetric(metricName: testCase.click))

            // Then
            XCTAssertEqual(pixelKitMock.actualFireCalls.count, countBeforeClick + 1, "\(testCase.origin) click")
            XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.aiChatSubscriptionFunnelClick.name)
            XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, ["origin": testCase.origin])
        }
    }

    func testSubscriptionFunnelPixelNames() {
        XCTAssertEqual(Pixel.Event.aiChatSubscriptionFunnelImpression.name, "m_aichat_subscription-funnel_impression")
        XCTAssertEqual(Pixel.Event.aiChatSubscriptionFunnelClick.name, "m_aichat_subscription-funnel_click")
    }

    // MARK: - Integration Tests

    func testMultiplePixelFiresWithConsistentParameters() {
        // Given
        let timeElapsed = 20
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: pixelKitMock)

        // When
        handler.fireOpenAIChat()
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidSubmitPrompt))
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidOpenHistory))

        // Then
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 3)

        // All pixels should have the same timestamp parameter
        for capturedPixel in pixelKitMock.actualFireCalls {
            XCTAssertEqual(capturedPixel.additionalParameters?["delta-timestamp-minutes"], "20")
        }
    }
}
