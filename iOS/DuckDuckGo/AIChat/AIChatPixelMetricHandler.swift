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
import Subscription

// MARK: - Protocol

protocol AIChatPixelMetricHandling {
    func fireOpenAIChat()
    func firePixelWithMetric(_ metric: AIChatMetric)
}

/// Maps minutes since the Duck.ai session started into a coarse bucket label,
/// using the same label dialect as m_app_return's time_away_bucket.
enum AIChatSessionDeltaBucket {
    static func bucket(forMinutes minutes: Int) -> String {
        switch minutes {
        case ..<5: return "lt_5m"
        case ..<30: return "5_30m"
        case ..<60: return "30_60m"
        case ..<240: return "1_4h"
        case ..<1440: return "4_24h"
        default: return "gt_24h"
        }
    }
}

// MARK: - Implementation

final class AIChatPixelMetricHandler: AIChatPixelMetricHandling {

    // MARK: - Private Properties

    private let timeElapsedInMinutes: Int?
    private let pixelFiring: PixelFiring.Type
    private let featureDiscovery: FeatureDiscovery
    private let timestampParameterKey = "delta-timestamp-bucket"

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

        .userDidViewProUpgradeDisclaimerBanner: (.aiChatSubscriptionFunnelImpression, .duckAIDisclaimerBanner),
        .userDidClickProUpgradeDisclaimerBannerButton: (.aiChatSubscriptionFunnelClick, .duckAIDisclaimerBanner),

        .userDidViewVoiceChatLimitModal: (.aiChatSubscriptionFunnelImpression, .duckAIVoiceChatLimit),
        .userDidClickVoiceChatLimitModalSubscribeButton: (.aiChatSubscriptionFunnelClick, .duckAIVoiceChatLimit),

        .userDidViewVoiceChatDurationLimitModal: (.aiChatSubscriptionFunnelImpression, .duckAIVoiceChatDurationLimit),
        .userDidClickVoiceChatDurationLimitModalSubscribeButton: (.aiChatSubscriptionFunnelClick, .duckAIVoiceChatDurationLimit)
    ]

    // MARK: - Initialization

    init(timeElapsedInMinutes: Int? = nil,
         pixelFiring: PixelFiring.Type = Pixel.self,
         featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery()) {
        self.timeElapsedInMinutes = timeElapsedInMinutes
        self.pixelFiring = pixelFiring
        self.featureDiscovery = featureDiscovery
    }

    // MARK: - AIChatPixelMetricHandling

    func fireOpenAIChat() {
        let parameters = timestampParameters ?? [:]
        pixelFiring.fire(.aiChatOpen, withAdditionalParameters: parameters)
    }

    func firePixelWithMetric(_ metric: AIChatMetric) {
        if let event = Self.metricToEventMap[metric.metricName] {
            var parameters: [String: String] = [:]
            if metric.shouldIncludeTimestampParameters {
                parameters = timestampParameters ?? [:]
            }

            // Native submission paths mark the flag first, so this claims first_prompt_new_install
            // only for submissions made directly in the frontend composer (e.g. iPad AI tabs).
            let isPromptSubmission = Self.promptSubmissionMetrics.contains(metric.metricName)
            if isPromptSubmission && featureDiscovery.isFirstDuckAIPromptNewInstall {
                parameters[PixelParameters.aiChatFirstPromptNewInstall] = "true"
            }

            pixelFiring.fire(event, withAdditionalParameters: parameters)

            if isPromptSubmission {
                featureDiscovery.markDuckAIPromptSubmitted()
            }
            return
        }

        if let funnelPixel = Self.funnelMetricToPixelMap[metric.metricName] {
            pixelFiring.fire(funnelPixel.event,
                             withAdditionalParameters: [AttributionParameter.origin: funnelPixel.origin.rawValue])
            return
        }
    }

    // MARK: - Private Helpers

    private var timestampParameters: [String: String]? {
        guard let timeElapsed = timeElapsedInMinutes else { return nil }
        return [timestampParameterKey: AIChatSessionDeltaBucket.bucket(forMinutes: timeElapsed)]
    }
}

// MARK: - Voice Entry Point Source

/// Identifies the entry point from which the user launched Duck.ai voice mode.
enum VoiceEntryPointSource: String {
    case ntp
    case toolbar
    case addressBar = "address_bar"
    case controlCenter = "widget.controlcenter"
    case lockscreenComplication = "widget.lockscreen.complication"
    case quickActions = "widget.quickactions"
    case quickActionsMedium = "widget.quickactions.medium"
    case siri
}
