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

final class AIChatPixelMetricHandlerTests: XCTestCase {

    private var handler: AIChatPixelMetricHandler!

    override func tearDown() {
        handler = nil
        PixelFiringMock.tearDown()
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationWithTimeElapsed() {
        // Given
        let timeElapsed = 5

        // When
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: PixelFiringMock.self)

        // Then
        XCTAssertNotNil(handler)
    }

    func testInitializationWithNilTimeElapsed() {
        // When
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: PixelFiringMock.self)

        // Then
        XCTAssertNotNil(handler)
    }

    // MARK: - fireOpenAIChat Tests

    func testFireOpenAIChatWithoutTimeElapsed() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: PixelFiringMock.self)

        // When
        handler.fireOpenAIChat()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatOpen.name)
        XCTAssertTrue(PixelFiringMock.lastParams?.isEmpty ?? false)
    }

    func testFireOpenAIChatWithTimeElapsed() {
        // Given
        let timeElapsed = 10
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: PixelFiringMock.self)

        // When
        handler.fireOpenAIChat()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatOpen.name)
        XCTAssertEqual(PixelFiringMock.lastParams?["delta-timestamp-minutes"], "10")
    }

    func testFireOpenAIChatWithZeroTimeElapsed() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: 0, pixelFiring: PixelFiringMock.self)

        // When
        handler.fireOpenAIChat()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatOpen.name)
        XCTAssertEqual(PixelFiringMock.lastParams?["delta-timestamp-minutes"], "0")
    }

    // MARK: - firePixelWithMetric Tests

    func testFirePixelWithMetricForKnownMetric() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: PixelFiringMock.self)
        let metric = AIChatMetric(metricName: .userDidSubmitPrompt)

        // When
        handler.firePixelWithMetric(metric)

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatMetricSentPromptOngoingChat.name)
        XCTAssertTrue(PixelFiringMock.lastParams?.isEmpty ?? false)
    }

    func testFirePixelWithMetricForKnownMetricWithTimeElapsed() {
        // Given
        let timeElapsed = 15
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: PixelFiringMock.self)
        let metric = AIChatMetric(metricName: .userDidSubmitFirstPrompt)

        // When
        handler.firePixelWithMetric(metric)

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatMetricStartNewConversation.name)
        XCTAssertEqual(PixelFiringMock.lastParams?["delta-timestamp-minutes"], "15")
    }

    func testFirePixelWithMetricForAllKnownMetrics() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: PixelFiringMock.self)
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

            XCTAssertEqual(PixelFiringMock.allPixelsFired.count, index + 1)
            XCTAssertEqual(PixelFiringMock.allPixelsFired[index].pixelName, testCase.1.name)
        }
    }

    func testFirePixelWithMetricForKeyboardReturnKey() {
        // Given
        let timeElapsed = 15
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: PixelFiringMock.self)
        let metric = AIChatMetric(metricName: .userDidTapKeyboardReturnKey)

        // When
        handler.firePixelWithMetric(metric)

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatMetricDuckAIKeyboardReturnPressed.name)
        XCTAssertTrue(PixelFiringMock.lastParams?.isEmpty ?? false)
    }

    func testFirePixelWithMetricForUnknownMetricDoesNothing() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: PixelFiringMock.self)

        // When - a metric name in neither the engagement nor the funnel table
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidAcceptTermsAndConditions))

        // Then
        XCTAssertTrue(PixelFiringMock.allPixelsFired.isEmpty)
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
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: 7, pixelFiring: PixelFiringMock.self)

        for testCase in testCases {
            // When
            PixelFiringMock.tearDown()
            handler.firePixelWithMetric(AIChatMetric(metricName: testCase.view))

            // Then
            XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1, "\(testCase.origin) view")
            XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatSubscriptionFunnelImpression.name)
            XCTAssertEqual(PixelFiringMock.lastParams, ["origin": testCase.origin])

            // When
            PixelFiringMock.tearDown()
            handler.firePixelWithMetric(AIChatMetric(metricName: testCase.click))

            // Then
            XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1, "\(testCase.origin) click")
            XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatSubscriptionFunnelClick.name)
            XCTAssertEqual(PixelFiringMock.lastParams, ["origin": testCase.origin])
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
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: PixelFiringMock.self)

        // When
        handler.fireOpenAIChat()
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidSubmitPrompt))
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidOpenHistory))

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 3)

        // All pixels should have the same timestamp parameter
        for capturedPixel in PixelFiringMock.allPixelsFired {
            XCTAssertEqual(capturedPixel.params?["delta-timestamp-minutes"], "20")
        }
    }
}
