//
//  OnboardingAIModelsFallback.swift
//  DuckDuckGo
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
import PrivacyConfig
import Core

// MARK: - Fallback

/// Supplies a curated fallback AI model list, used when the `/models` API is unavailable.
/// Backed by the `onboardingAIModelsFallback` key in `iOSBrowserConfig` settings in privacy config.
protocol OnboardingAIModelsFallbackProviding {
    var aiModels: OnboardingAIModelResponse { get }
}

/// Reads the fallback payload from the `onboardingAIModelsFallback` key in `iOSBrowserConfig` settings.
///
/// ```json
/// { "defaultModelId": "gpt-5", "models": [{ "id": "gpt-5", "provider": "openai", "modelShortName": "GPT-5" }] }
/// ```
struct OnboardingAIModelsFallback: OnboardingAIModelsFallbackProviding {
    /// Compiled-in last resort so the picker is never empty, even with no config and no network.
    /// Mirrors what the resolver picks from the models API: one accessible model per supported
    /// provider, in display order (ChatGPT, Claude, Mistral). Bypasses the resolver, so this array
    /// order is the final display order. Default is OpenAI.
    private static let lastResortFallback = OnboardingAIModelResponse(
        models: [
            OnboardingAIModelOption(id: "gpt-5.4-nano", provider: .openai, modelShortName: "5.4-nano"),
            OnboardingAIModelOption(id: "claude-haiku-4-5", provider: .anthropic, modelShortName: "Haiku 4.5"),
            OnboardingAIModelOption(id: "mistral-small-2603", provider: .mistral, modelShortName: "Mistral")
        ],
        defaultModelId: "gpt-5.4-nano"
    )

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    var aiModels: OnboardingAIModelResponse {
        remoteFallback ?? Self.lastResortFallback
    }

    private var remoteFallback: OnboardingAIModelResponse? {
        let remoteSettings = privacyConfigurationManager.privacyConfig.settings(for: .iOSBrowserConfig)

        guard
            let aiModelsFallback = remoteSettings[OnboardingAIModelsFallbackPayload.settingsKey] as? [String: Any],
            let data = try? JSONSerialization.data(withJSONObject: aiModelsFallback),
            let payload = try? JSONDecoder().decode(OnboardingAIModelsFallbackPayload.self, from: data),
            !payload.response.models.isEmpty // If models is empty fallback to hardcoded version
        else {
            return nil
        }
        return payload.response
    }
}

private struct OnboardingAIModelsFallbackPayload: Decodable {
    static let settingsKey = "onboardingAIModelsFallback"

    struct Model: Decodable {
        let id: String
        let provider: String
        let modelShortName: String?
    }

    /// Decodes a single entry without failing the whole list when that entry is malformed.
    struct LossyModel: Decodable {
        let model: Model?

        init(from decoder: Decoder) throws {
            model = try? Model(from: decoder)
        }
    }

    let defaultModelId: String?
    let models: [LossyModel]

    var response: OnboardingAIModelResponse {
        let options = models.compactMap { entry -> OnboardingAIModelOption? in
            guard let model = entry.model, let provider = OnboardingAIProvider(rawValue: model.provider) else { return nil }
            return OnboardingAIModelOption(id: model.id, provider: provider, modelShortName: model.modelShortName)
        }
        // If the default isn't among the kept models, prefer the OpenAI one, otherwise the first, so the picker always has a selection.
        let defaultId = options.contains { $0.id == defaultModelId }
            ? defaultModelId
            : (options.first { $0.provider == .openai } ?? options.first)?.id
        return OnboardingAIModelResponse(models: options, defaultModelId: defaultId)
    }
}
