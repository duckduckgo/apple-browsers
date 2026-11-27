//
//  AIChatLocalModelPixel.swift
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

import Foundation

/// A local-model pixel before the app adds its platform suffix. Defined here so iOS and macOS send
/// the same names and values. Run results aren't here: Duck.ai counts them itself.
public enum AIChatLocalModelPixel: Equatable, Sendable {

    /// Sent only while the feature flag is on.
    case state(selected: AIChatPageSummariesModel, state: AIChatLocalModelState, availability: AIChatLocalModelAvailability)
    /// The prompt Duck.ai asks for is showing.
    case promoShown
    /// The prompt closed without Turn On. Turn On sends `selected` from the service instead.
    case promoClosed
    /// The user changed the model that writes page summaries.
    case selected(AIChatPageSummariesModel, source: SelectionSource)
    case runStarted(engine: AIChatPageSummariesModel, task: AIChatLocalModelTask)

    public enum SelectionSource: String, Sendable {
        case duckAIPromo = "duckai_promo"
        case settings
    }

    public enum Frequency: Sendable {
        case standard
        case daily
        case dailyAndCount
    }

    public var name: String {
        switch self {
        case .state: return "aichat_local_model_state"
        case .promoShown: return "aichat_local_model_promo_shown"
        case .promoClosed: return "aichat_local_model_promo_closed"
        case .selected: return "aichat_local_model_selected"
        case .runStarted: return "aichat_local_model_run_started"
        }
    }

    public var parameters: [String: String] {
        switch self {
        case .state(let selected, let state, let availability):
            return ["selected": selected.pixelValue, "state": state.rawValue, "system_model": availability.pixelValue]
        case .promoShown, .promoClosed:
            return ["surface": "duckai"]
        case .selected(let model, let source):
            return ["engine": model.pixelValue, "source": source.rawValue]
        case .runStarted(let engine, let task):
            return ["engine": engine.pixelValue, "task": task.rawValue]
        }
    }

    public var frequency: Frequency {
        switch self {
        case .state, .runStarted: return .daily
        case .promoShown, .promoClosed: return .dailyAndCount
        case .selected: return .standard
        }
    }
}

/// Sends local-model pixels. Each app implements it with PixelKit, which this package doesn't use.
/// Not tied to the main actor, so the apps can build one in a default argument.
public protocol AIChatLocalModelInstrumentation {
    func fire(_ pixel: AIChatLocalModelPixel)
}

private extension AIChatPageSummariesModel {

    /// The kind of engine, not the model, so a downloaded model can reuse the same pixels.
    var pixelValue: String {
        switch self {
        case .duckAI: return "cloud"
        case .appleIntelligence: return "system"
        }
    }
}

private extension AIChatLocalModelAvailability {

    var pixelValue: String {
        switch self {
        case .available: return "available"
        case .appleIntelligenceNotEnabled: return "not_enabled"
        case .modelNotReady: return "not_ready"
        case .deviceNotEligible: return "not_eligible"
        case .unsupportedOS: return "unsupported_os"
        }
    }
}
