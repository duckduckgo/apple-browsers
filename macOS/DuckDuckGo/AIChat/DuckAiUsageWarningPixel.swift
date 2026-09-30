//
//  DuckAiUsageWarningPixel.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import AIChat
import os.log
import PixelKit

/// Which native surface reported the card. Shares iOS's raw values where the surfaces match, so the
/// two platforms' series can be read together.
enum DuckAiUsageWarningPixelSurface: String {
    case addressBar = "address_bar"
    case promptBar = "prompt_bar"
}

/// The Duck.ai usage-warning card's pixels, name-for-name with iOS. Which message the user saw is in
/// the name rather than in a parameter, so each state is one series; the window, the rung and the
/// model id are parameters.
enum DuckAiUsageWarningPixel: PixelKit.Event {

    /// What the card was about when the pixel fired. Only the fields the state has are sent.
    struct Context: Equatable {
        let surface: DuckAiUsageWarningPixelSurface
        let window: DuckAiUsageWindow?
        let percentBucket: Int?
        let modelId: String?

        init(exposure: DuckAiUsageWarningExposure, surface: DuckAiUsageWarningPixelSurface) {
            self.surface = surface
            self.window = exposure.window
            self.percentBucket = exposure.percentBucket
            self.modelId = exposure.modelId
        }
    }

    private enum Parameter {
        static let surface = "surface"
        static let window = "window"
        static let percentBucket = "percent_bucket"
        static let modelId = "model_id"
    }

    case approachingShown(Context)
    case approachingDismissed(Context)
    case approachingPromptSubmitted(Context)
    case approachingModelSwitched(Context)
    case approachingAbandoned(Context)

    case limitReachedShown(Context)
    case limitReachedPromptSubmitted(Context)
    case limitReachedModelSwitched(Context)
    case limitReachedAbandoned(Context)

    case switchModelTapped(Context)
    case upsellTapped(Context)

    case highUsageModelNoticeShown(Context)
    case highUsageModelNoticeDismissed(Context)
    case highUsageModelNoticePromptSubmitted(Context)
    case highUsageModelNoticeModelSwitched(Context)
    case highUsageModelNoticeAbandoned(Context)

    var name: String {
        switch self {
        case .approachingShown: return "aichat_usage_warning_approaching_shown"
        case .approachingDismissed: return "aichat_usage_warning_approaching_dismissed"
        case .approachingPromptSubmitted: return "aichat_usage_warning_approaching_prompt_submitted"
        case .approachingModelSwitched: return "aichat_usage_warning_approaching_model_switched"
        case .approachingAbandoned: return "aichat_usage_warning_approaching_abandoned"
        case .limitReachedShown: return "aichat_usage_warning_limit_reached_shown"
        case .limitReachedPromptSubmitted: return "aichat_usage_warning_limit_reached_prompt_submitted"
        case .limitReachedModelSwitched: return "aichat_usage_warning_limit_reached_model_switched"
        case .limitReachedAbandoned: return "aichat_usage_warning_limit_reached_abandoned"
        case .switchModelTapped: return "aichat_usage_warning_switch_model_tapped"
        case .upsellTapped: return "aichat_usage_warning_upsell_tapped"
        case .highUsageModelNoticeShown: return "aichat_high_usage_model_notice_shown"
        case .highUsageModelNoticeDismissed: return "aichat_high_usage_model_notice_dismissed"
        case .highUsageModelNoticePromptSubmitted: return "aichat_high_usage_model_notice_prompt_submitted"
        case .highUsageModelNoticeModelSwitched: return "aichat_high_usage_model_notice_model_switched"
        case .highUsageModelNoticeAbandoned: return "aichat_high_usage_model_notice_abandoned"
        }
    }

    var parameters: [String: String]? {
        var parameters = [Parameter.surface: context.surface.rawValue]
        if let window = context.window {
            parameters[Parameter.window] = window.rawValue
        }
        if let percentBucket = context.percentBucket {
            parameters[Parameter.percentBucket] = String(percentBucket)
        }
        if let modelId = context.modelId {
            parameters[Parameter.modelId] = modelId
        }
        return parameters
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    private var context: Context {
        switch self {
        case .approachingShown(let context),
             .approachingDismissed(let context),
             .approachingPromptSubmitted(let context),
             .approachingModelSwitched(let context),
             .approachingAbandoned(let context),
             .limitReachedShown(let context),
             .limitReachedPromptSubmitted(let context),
             .limitReachedModelSwitched(let context),
             .limitReachedAbandoned(let context),
             .switchModelTapped(let context),
             .upsellTapped(let context),
             .highUsageModelNoticeShown(let context),
             .highUsageModelNoticeDismissed(let context),
             .highUsageModelNoticePromptSubmitted(let context),
             .highUsageModelNoticeModelSwitched(let context),
             .highUsageModelNoticeAbandoned(let context):
            return context
        }
    }
}

extension DuckAiUsageWarningPixel {

    /// `nil` where the state cannot produce the interaction, so an impossible combination reports
    /// nothing rather than landing on another state's series. A reached limit has no close button.
    init?(event: DuckAiUsageWarningMeasurementEvent, surface: DuckAiUsageWarningPixelSurface) {
        switch event {
        case .shown(let exposure):
            let context = Context(exposure: exposure, surface: surface)
            switch exposure.kind {
            case .approaching: self = .approachingShown(context)
            case .limitReached: self = .limitReachedShown(context)
            case .highUsageModelNotice: self = .highUsageModelNoticeShown(context)
            }
        case .dismissed(let exposure):
            let context = Context(exposure: exposure, surface: surface)
            switch exposure.kind {
            case .approaching: self = .approachingDismissed(context)
            case .highUsageModelNotice: self = .highUsageModelNoticeDismissed(context)
            case .limitReached: return nil
            }
        case .promptSubmitted(let exposure):
            let context = Context(exposure: exposure, surface: surface)
            switch exposure.kind {
            case .approaching: self = .approachingPromptSubmitted(context)
            case .limitReached: self = .limitReachedPromptSubmitted(context)
            case .highUsageModelNotice: self = .highUsageModelNoticePromptSubmitted(context)
            }
        case .modelSwitched(let exposure):
            let context = Context(exposure: exposure, surface: surface)
            switch exposure.kind {
            case .approaching: self = .approachingModelSwitched(context)
            case .limitReached: self = .limitReachedModelSwitched(context)
            case .highUsageModelNotice: self = .highUsageModelNoticeModelSwitched(context)
            }
        case .abandoned(let exposure):
            let context = Context(exposure: exposure, surface: surface)
            switch exposure.kind {
            case .approaching: self = .approachingAbandoned(context)
            case .limitReached: self = .limitReachedAbandoned(context)
            case .highUsageModelNotice: self = .highUsageModelNoticeAbandoned(context)
            }
        // The CTA identifies itself, so these two are one series each across the states offering them.
        case .switchModelTapped(let exposure):
            self = .switchModelTapped(Context(exposure: exposure, surface: surface))
        case .upsellTapped(let exposure):
            self = .upsellTapped(Context(exposure: exposure, surface: surface))
        }
    }
}

// MARK: - Adapter

/// Fires the shared measurement's events as this app's pixels. One container VC serves the address
/// bar and the Prompt Bar, so the surface comes from the one it was built for.
struct DuckAiUsageWarningPixelAdapter: DuckAiUsageWarningPixelFiring {

    private let surface: DuckAiUsageWarningPixelSurface
    private let pixelFiring: PixelFiring?

    init(surface: DuckAiUsageWarningPixelSurface, pixelFiring: PixelFiring? = PixelKit.shared) {
        self.surface = surface
        self.pixelFiring = pixelFiring
    }

    func fire(_ event: DuckAiUsageWarningMeasurementEvent) {
        guard let pixel = DuckAiUsageWarningPixel(event: event, surface: surface) else { return }

        Logger.aiChat.debug("Duck.ai usage warning pixel: \(pixel.name, privacy: .public)")
        // `Options.default` carries the app version, which is what these definitions declare.
        pixelFiring?.fire(pixel, frequency: .dailyAndCount)
    }
}
