//
//  AIChatMetricName.swift
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

/// https://app.asana.com/1/137249556945/project/481882893211075/task/1210422904669751?focus=true
/// Data structure sent from AI Chat to the native layer
public enum AIChatMetricName: String, Codable {
    case userDidSubmitPrompt
    case userDidSubmitFirstPrompt
    case userDidOpenHistory
    case userDidSelectFirstHistoryItem
    case userDidCreateNewChat
    case userDidTapKeyboardReturnKey
    case userDidAcceptTermsAndConditions
    case userDidSelectSuggestion
    case userDidViewSuggestions

    // MARK: - Subscription funnel metrics
    // Reported by the frontend only inside a native app, where its own website pixel is suppressed.
    // https://app.asana.com/1/137249556945/task/1216395339071571
    case userDidViewAiSidebarUpgradeButton
    case userDidViewActivateSubscriptionBanner
    case userDidViewFreePlanBadge
    case userDidViewFreeLimitMessage
    case userDidViewImageGenerationLimitMessage
    case userDidViewPlusLimitMessage
    case userDidViewPromotionCard
    case userDidViewSettingsSubscribeButton
    case userDidViewSettingsResubscribeButton
    case userDidViewProUpgradeDisclaimerBanner
    case userDidViewVoiceChatLimitModal
    case userDidViewVoiceChatDurationLimitModal
    case userDidViewModelPickerUpgrade
    case userDidViewReasoningDropdownUpgrade
    case userDidViewSwitchModelUpgrade

    case userDidClickAiSidebarUpgradeButton
    case userDidClickActivateSubscriptionButton
    case userDidClickFreePlanUpgradeButton
    case userDidClickFreeLimitSubscribeLink
    case userDidClickImageGenerationLimitSubscribeButton
    case userDidClickPlusLimitUpgradeLink
    case userDidClickPromotionCardButton
    case userDidClickSettingsSubscribeButton
    case userDidClickSettingsResubscribeButton
    case userDidClickProUpgradeDisclaimerBannerButton
    case userDidClickVoiceChatLimitModalSubscribeButton
    case userDidClickVoiceChatDurationLimitModalSubscribeButton
    case userDidClickModelPickerUpgrade
    case userDidClickReasoningDropdownUpgrade
    case userDidClickSwitchModelUpgrade

    // MARK: - Subscription funnel modal metrics
    // The subscribe / upgrade-to-Pro modal the funnel entry points above open. These carry `source`,
    // naming the entry point the modal was opened from.
    case userDidOpenSubscribeModal
    case userDidClickSubscribeOnSubscribeModal
    case userDidClickActivateOnSubscribeModal
    case userDidOpenUpgradeToProModal
    case userDidClickUpgradeOnUpgradeToProModal

    // MARK: - Browser tools answer metrics
    // Sent only when `AIChatNativeConfigValues.supportsBrowserToolsAnswerMetrics` is true. They carry
    // `modelTier` and `browserTools`; the rated one also carries `rating`.
    case browserToolsAnswerCompleted
    case browserToolsAnswerRated
}

// Model tier for AI Chat metrics
public enum AIChatModelTier: String, Codable {
    case free
    case plus
    case pro
    case `internal`
    case unknown
}

public struct AIChatMetric: Codable {
    public let metricName: AIChatMetricName
    public let modelTier: AIChatModelTier?
    /// Fixed catalog key identifying the tapped suggestion (e.g. `summarize-page`). Carried by `userDidSelectSuggestion`.
    public let suggestionId: String?
    /// Coarse page classification the FE derived from JSON-LD/OpenGraph. Decoded as a plain string so a new FE
    /// page type never breaks decoding. Carried by `userDidSelectSuggestion` and `userDidViewSuggestions`.
    public let pageType: String?
    /// Whether the shown suggestions were smart (page-tailored) rather than generic. Carried by `userDidViewSuggestions`.
    public let isSmart: Bool?
    /// Funnel entry point a modal was opened from (e.g. `freelimit`). Decoded as a plain string so a new FE
    /// slug never breaks decoding. Carried by the subscription funnel modal metrics.
    public let source: String?
    /// Every distinct browser tool an answer called. Carried by the browser tools answer metrics.
    public let browserTools: [AIChatBrowserToolAnswerTool]?
    /// `up` or `down`. Decoded as a plain string, checked by the receiver. Carried by `browserToolsAnswerRated`.
    public let rating: String?

     public init(metricName: AIChatMetricName, modelTier: AIChatModelTier? = nil, suggestionId: String? = nil, pageType: String? = nil, isSmart: Bool? = nil, source: String? = nil,
                 browserTools: [AIChatBrowserToolAnswerTool]? = nil, rating: String? = nil) {
         self.metricName = metricName
         self.modelTier = modelTier
         self.suggestionId = suggestionId
         self.pageType = pageType
         self.isSmart = isSmart
         self.source = source
         self.browserTools = browserTools
         self.rating = rating
     }
}

/// One browser tool an answer called. Both fields are plain strings so a new FE value never breaks decoding;
/// the receiver drops anything it doesn't know.
public struct AIChatBrowserToolAnswerTool: Codable, Equatable {
    /// Capability name, e.g. `listOpenTabs`.
    public let name: String
    /// `success` if any call succeeded, else `not_allowed` if any was denied or cancelled, else `error`.
    public let result: String

    public init(name: String, result: String) {
        self.name = name
        self.result = result
    }
}

extension AIChatMetric {
    public var shouldIncludeTimestampParameters: Bool {
        switch metricName {
        case .userDidTapKeyboardReturnKey:
            return false
        default:
            return true
        }
    }
}
