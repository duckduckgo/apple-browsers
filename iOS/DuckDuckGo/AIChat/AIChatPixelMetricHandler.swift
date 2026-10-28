//
//  AIChatPixelMetricHandler.swift
//  DuckDuckGo
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

import Foundation
import AIChat
import BrowserServicesKit
import Core
import PixelKit
import Subscription

// MARK: - Protocol

protocol AIChatPixelMetricHandling {
    func fireOpenAIChat()
    func firePixelWithMetric(_ metric: AIChatMetric)
}

// MARK: - Implementation

final class AIChatPixelMetricHandler: AIChatPixelMetricHandling {

    // MARK: - Private Properties

    private let timeElapsedInMinutes: Int?
    private let pixelFiring: (any PixelKitFiring)?
    private let featureDiscovery: FeatureDiscovery
    private let promptContextProvider: DuckAIPromptPixelContextProviding?
    private let usageContextProvider: UsageContextProviding
    private let timestampParameterKey = "delta-timestamp-minutes"

    enum PromptParameter {
        static let surface = "surface"
        static let unattributedSource = "unattributed"
    }

    /// The metrics the frontend reports when a prompt is submitted through its own composer.
    private static let promptSubmissionMetrics: Set<AIChatMetricName> = [.userDidSubmitPrompt, .userDidSubmitFirstPrompt]

    static let metricToEventMap: [AIChatMetricName: Pixel.Event] = [
        .userDidSubmitPrompt: .aiChatMetricSentPromptOngoingChat,
        .userDidSubmitFirstPrompt: .aiChatMetricStartNewConversation,
        .userDidOpenHistory: .aiChatMetricOpenHistory,
        .userDidSelectFirstHistoryItem: .aiChatMetricOpenMostRecentHistoryChat,
        .userDidCreateNewChat: .aiChatMetricStartNewConversationButtonClicked,
        .userDidTapKeyboardReturnKey: .aiChatMetricDuckAIKeyboardReturnPressed
    ]

    /// Subscription-funnel metrics: metric name → the pixel to fire and the `origin` value identifying the
    /// entry point. Each of the ten frontend-reported entry points contributes a view metric (impression)
    /// and a click metric (click).
    ///
    /// `userDidViewFreePlanBadge` and `userDidClickFreePlanUpgradeButton` are **deliberately absent**. That
    /// entry point is native on iOS.
    static let funnelMetricToPixelMap: [AIChatMetricName: (event: Pixel.Event, origin: SubscriptionFunnelOrigin)] = [
        .userDidViewAiSidebarUpgradeButton: (.aiChatSubscriptionFunnelImpression, .duckAIAiSidebar),
        .userDidClickAiSidebarUpgradeButton: (.aiChatSubscriptionFunnelClick, .duckAIAiSidebar),

        .userDidViewActivateSubscriptionBanner: (.aiChatSubscriptionFunnelImpression, .duckAIActivateSubscription),
        .userDidClickActivateSubscriptionButton: (.aiChatSubscriptionFunnelClick, .duckAIActivateSubscription),

        .userDidViewFreeLimitMessage: (.aiChatSubscriptionFunnelImpression, .duckAIFreeLimit),
        .userDidClickFreeLimitSubscribeLink: (.aiChatSubscriptionFunnelClick, .duckAIFreeLimit),

        .userDidViewImageGenerationLimitMessage: (.aiChatSubscriptionFunnelImpression, .duckAIImageGenerationLimit),
        .userDidClickImageGenerationLimitSubscribeButton: (.aiChatSubscriptionFunnelClick, .duckAIImageGenerationLimit),

        .userDidViewPlusLimitMessage: (.aiChatSubscriptionFunnelImpression, .duckAIPlusLimit),
        .userDidClickPlusLimitUpgradeLink: (.aiChatSubscriptionFunnelClick, .duckAIPlusLimit),

        .userDidViewPromotionCard: (.aiChatSubscriptionFunnelImpression, .duckAIPromotionCard),
        .userDidClickPromotionCardButton: (.aiChatSubscriptionFunnelClick, .duckAIPromotionCard),

        .userDidViewSettingsSubscribeButton: (.aiChatSubscriptionFunnelImpression, .duckAISettings),
        .userDidClickSettingsSubscribeButton: (.aiChatSubscriptionFunnelClick, .duckAISettings),
        .userDidViewSettingsResubscribeButton: (.aiChatSubscriptionFunnelImpression, .duckAISettings),
        .userDidClickSettingsResubscribeButton: (.aiChatSubscriptionFunnelClick, .duckAISettings),

        .userDidViewProUpgradeDisclaimerBanner: (.aiChatSubscriptionFunnelImpression, .duckAIDisclaimerBanner),
        .userDidClickProUpgradeDisclaimerBannerButton: (.aiChatSubscriptionFunnelClick, .duckAIDisclaimerBanner),

        .userDidViewVoiceChatLimitModal: (.aiChatSubscriptionFunnelImpression, .duckAIVoiceChatLimit),
        .userDidClickVoiceChatLimitModalSubscribeButton: (.aiChatSubscriptionFunnelClick, .duckAIVoiceChatLimit),

        .userDidViewVoiceChatDurationLimitModal: (.aiChatSubscriptionFunnelImpression, .duckAIVoiceChatDurationLimit),
        .userDidClickVoiceChatDurationLimitModalSubscribeButton: (.aiChatSubscriptionFunnelClick, .duckAIVoiceChatDurationLimit)
    ]

    // MARK: - Initialization

    init(timeElapsedInMinutes: Int? = nil,
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared,
         featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery(),
         promptContextProvider: DuckAIPromptPixelContextProviding? = nil,
         usageContextProvider: UsageContextProviding = UsageContextProvider()) {
        self.timeElapsedInMinutes = timeElapsedInMinutes
        self.pixelFiring = pixelFiring
        self.featureDiscovery = featureDiscovery
        self.promptContextProvider = promptContextProvider
        self.usageContextProvider = usageContextProvider
    }

    // MARK: - AIChatPixelMetricHandling

    func fireOpenAIChat() {
        let parameters = timestampParameters(minutes: timeElapsedInMinutes)
        pixelFiring?.fire(Pixel.Event.aiChatOpen, options: .parameters(parameters))
    }

    func firePixelWithMetric(_ metric: AIChatMetric) {
        if let event = Self.metricToEventMap[metric.metricName] {
            var parameters: [String: String] = [:]
            if metric.shouldIncludeTimestampParameters {
                parameters = timestampParameters(minutes: timeElapsedInMinutes ?? promptContextProvider?.minutesSincePageLoad)
            }

            // Native submission paths mark the flag first, so this claims first_prompt_new_install
            // only for submissions made directly in the frontend composer (e.g. iPad AI tabs).
            let isPromptSubmission = Self.promptSubmissionMetrics.contains(metric.metricName)
            if isPromptSubmission && featureDiscovery.isFirstDuckAIPromptNewInstall {
                parameters[PixelParameters.aiChatFirstPromptNewInstall] = "true"
            }
            if isPromptSubmission {
                parameters.merge(promptAttributionParameters()) { $1 }
            }

            pixelFiring?.fire(event, options: .parameters(parameters))

            if isPromptSubmission {
                featureDiscovery.markDuckAIPromptSubmitted()
            }
            return
        }

        if let funnelPixel = Self.funnelMetricToPixelMap[metric.metricName] {
            pixelFiring?.fire(funnelPixel.event,
                              options: .parameters([AttributionParameter.origin: funnelPixel.origin.rawValue]))
            return
        }
    }

    // MARK: - Private Helpers

    private func timestampParameters(minutes: Int?) -> [String: String] {
        guard let minutes else { return [:] }
        return [timestampParameterKey: "\(minutes)"]
    }

    private func promptAttributionParameters() -> [String: String] {
        guard let context = promptContextProvider?.contextForSubmittedPrompt() else { return [:] }
        return usageContextProvider.currentContext.parameters.merging([
            PixelParameters.source: context.source?.rawValue ?? PromptParameter.unattributedSource,
            PromptParameter.surface: context.surface.rawValue,
        ]) { $1 }
    }
}

// MARK: - Voice Entry Point Source

/// Identifies the entry point from which the user launched Duck.ai voice mode.
enum VoiceEntryPointSource: String {
    case menuBar = "menu_bar"
    case ntp
    case toolbar
    case addressBar = "address_bar"
    /// "New voice chat" on a Duck.ai page.
    case duckAI = "duck_ai"
    case controlCenter = "widget.controlcenter"
    case lockscreenComplication = "widget.lockscreen.complication"
    case quickActions = "widget.quickactions"
    case quickActionsMedium = "widget.quickactions.medium"
    case siri
}
