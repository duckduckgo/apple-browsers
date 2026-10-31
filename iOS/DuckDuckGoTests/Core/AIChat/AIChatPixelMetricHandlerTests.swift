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

import GameController
import XCTest
import BrowserServicesKitTestsUtils
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

    /// A user who has already submitted a Duck.ai prompt, so no first_prompt_new_install param is added.
    private static func returningUserFeatureDiscovery() -> MockFeatureDiscovery {
        let featureDiscovery = MockFeatureDiscovery()
        featureDiscovery.setReturnValue(true, for: .duckAIPrompt)
        return featureDiscovery
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
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil,
                                           pixelFiring: pixelKitMock,
                                           featureDiscovery: Self.returningUserFeatureDiscovery())
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
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed,
                                           pixelFiring: pixelKitMock,
                                           featureDiscovery: Self.returningUserFeatureDiscovery())
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
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil,
                                           pixelFiring: pixelKitMock,
                                           featureDiscovery: Self.returningUserFeatureDiscovery())
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

    // MARK: - First prompt

    func testWhenFirstEverPromptReportedByFrontendThenFirstPromptParamIsTrueAndFlagIsMarked() {
        // Given
        let featureDiscovery = MockFeatureDiscovery()
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil,
                                           pixelFiring: pixelKitMock,
                                           featureDiscovery: featureDiscovery)

        // When
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidSubmitPrompt))

        // Then
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["first_prompt_new_install"], "true")
        XCTAssertTrue(featureDiscovery.wasSetWasUsedBeforeCalled(for: .duckAIPrompt))
    }

    func testWhenReturningUserSubmitsPromptThenFirstPromptParamIsOmitted() {
        // Given
        let featureDiscovery = Self.returningUserFeatureDiscovery()
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil,
                                           pixelFiring: pixelKitMock,
                                           featureDiscovery: featureDiscovery)

        // When
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidSubmitFirstPrompt))

        // Then
        XCTAssertNil(pixelKitMock.actualFireCalls.last?.additionalParameters?["first_prompt_new_install"])
    }

    func testWhenNonPromptMetricFiresThenFirstPromptFlagIsUntouched() {
        // Given
        let featureDiscovery = MockFeatureDiscovery()
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil,
                                           pixelFiring: pixelKitMock,
                                           featureDiscovery: featureDiscovery)

        // When
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidOpenHistory))

        // Then
        XCTAssertNil(pixelKitMock.actualFireCalls.last?.additionalParameters?["first_prompt_new_install"])
        XCTAssertFalse(featureDiscovery.wasSetWasUsedBeforeCalled(for: .duckAIPrompt))
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
            ("funnel_duckai_ios__settings", .userDidViewSettingsResubscribeButton, .userDidClickSettingsResubscribeButton),
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
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed,
                                           pixelFiring: pixelKitMock,
                                           featureDiscovery: Self.returningUserFeatureDiscovery())

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

    // MARK: - Prompt attribution

    private struct FixedUsageContextProvider: UsageContextProviding {
        let currentContext = UsageContext(hardwareKeyboard: true, layout: .regular)
        let currentWindowMode: UsageContext.WindowMode = .partial
    }

    private func makeAttributedHandler(_ attribution: DuckAIPromptPixelContextProviding) -> AIChatPixelMetricHandler {
        AIChatPixelMetricHandler(pixelFiring: pixelKitMock,
                                 featureDiscovery: Self.returningUserFeatureDiscovery(),
                                 promptContextProvider: attribution,
                                 usageContextProvider: FixedUsageContextProvider())
    }

    func testPagePromptCarriesTheDoorThatOpenedThePage() {
        let attribution = DuckAIPromptAttribution()
        attribution.pageDidCommit(isDuckAI: true, entrySource: .tabsBarButton)
        handler = makeAttributedHandler(attribution)

        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidSubmitFirstPrompt))

        let parameters = pixelKitMock.actualFireCalls.last?.additionalParameters
        XCTAssertEqual(parameters?["source"], "tabs_bar_button")
        XCTAssertEqual(parameters?["surface"], "duck_ai")
        XCTAssertEqual(parameters?["layout"], "regular")
        XCTAssertEqual(parameters?["hardware_keyboard"], "true")
        XCTAssertEqual(parameters?["delta-timestamp-minutes"], "0")
    }

    func testPageLoadWithoutADoorIsUnattributed() {
        let attribution = DuckAIPromptAttribution()
        attribution.pageDidCommit(isDuckAI: true, entrySource: .tabsBarButton)
        attribution.pageDidCommit(isDuckAI: true, entrySource: nil)
        handler = makeAttributedHandler(attribution)

        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidSubmitPrompt))

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["source"], "unattributed")
    }

    func testAddressBarHandoverMarksOnlyTheNextPrompt() {
        let attribution = DuckAIPromptAttribution()
        attribution.addressBarWillHandOverPrompt()
        attribution.pageDidCommit(isDuckAI: true, entrySource: .ipadTogglePrompt)
        handler = makeAttributedHandler(attribution)

        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidSubmitFirstPrompt))
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidSubmitPrompt))

        let surfaces = pixelKitMock.actualFireCalls.map { $0.additionalParameters?["surface"] }
        XCTAssertEqual(surfaces, ["address_bar", "duck_ai"])
    }

    func testHandoverLapsesWhenAnotherPageLoads() {
        let attribution = DuckAIPromptAttribution()
        attribution.addressBarWillHandOverPrompt()
        attribution.pageDidCommit(isDuckAI: true, entrySource: .ipadTogglePrompt)
        attribution.pageDidCommit(isDuckAI: true, entrySource: nil)

        XCTAssertEqual(attribution.contextForSubmittedPrompt().surface, .duckAI)
    }

    func testLeavingDuckAIDropsAPendingHandover() {
        let attribution = DuckAIPromptAttribution()
        attribution.addressBarWillHandOverPrompt()
        attribution.pageDidCommit(isDuckAI: false, entrySource: nil)

        XCTAssertEqual(attribution.contextForSubmittedPrompt(),
                       DuckAIPromptPixelContext(source: nil, surface: .duckAI))
    }

    func testKeyboardMonitorWaitsForTheAppToBecomeActiveBeforeQueryingGameController() {
        let notificationCenter = NotificationCenter()
        var queryCount = 0
        let monitor = HardwareKeyboardMonitor(notificationCenter: notificationCenter, isConnectedNow: {
            queryCount += 1
            return true
        })
        XCTAssertEqual(queryCount, 0)
        XCTAssertNil(monitor.isConnected)

        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(queryCount, 1)
        XCTAssertEqual(monitor.isConnected, true)
    }

    func testUnknownHardwareKeyboardIsLeftOutOfThePixelParameters() {
        let parameters = UsageContext(hardwareKeyboard: nil, layout: .compact).parameters

        XCTAssertEqual(parameters, ["layout": "compact"])
    }

    func testKeyboardMonitorFollowsConnectAndDisconnectNotifications() {
        let notificationCenter = NotificationCenter()
        var isConnectedNow = false
        let monitor = HardwareKeyboardMonitor(notificationCenter: notificationCenter, isConnectedNow: { isConnectedNow })
        XCTAssertNil(monitor.isConnected)

        isConnectedNow = true
        notificationCenter.post(name: .GCKeyboardDidConnect, object: nil)
        XCTAssertEqual(monitor.isConnected, true)

        isConnectedNow = false
        notificationCenter.post(name: .GCKeyboardDidDisconnect, object: nil)
        XCTAssertEqual(monitor.isConnected, false)
    }

    func testContextualChatPromptsReportTheSheet() {
        handler = makeAttributedHandler(ContextualChatPromptPixelContext())

        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidSubmitPrompt))

        let parameters = pixelKitMock.actualFireCalls.last?.additionalParameters
        XCTAssertEqual(parameters?["source"], "contextual_chat")
        XCTAssertEqual(parameters?["surface"], "contextual_chat")
    }

    func testNonPromptMetricsCarryNoAttribution() {
        let attribution = DuckAIPromptAttribution()
        attribution.pageDidCommit(isDuckAI: true, entrySource: .tabsBarButton)
        handler = makeAttributedHandler(attribution)

        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidOpenHistory))

        XCTAssertNil(pixelKitMock.actualFireCalls.last?.additionalParameters?["source"])
    }
}
