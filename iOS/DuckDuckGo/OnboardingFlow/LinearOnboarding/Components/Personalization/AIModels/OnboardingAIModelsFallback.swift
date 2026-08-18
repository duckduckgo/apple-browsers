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
import FeatureFlags_iOS

// MARK: - Fallback

/// Supplies a curated fallback AI model list, used when the `/models` API is unavailable.
/// Backed by the onboarding `.onboardingFlowByDownloadReasonExperiment` subfeature's `settings` payload in privacy config
protocol OnboardingAIModelsFallbackProviding {
    var aiModels: OnboardingAIModelResponse { get }
}

/// Reads the fallback payload from the `onboardingFlowByDownloadReasonExperiment` subfeature settings.
///
/// Expected JSON shape (curated by us, so no access-filtering/dedup is applied .
/// `models` is a JSON-encoded string because the privacy-config subfeature `settings` schema only permits string values:
/// ```json
/// { "defaultModelId": "gpt-5", "models": "[{ \"id\": \"gpt-5\", \"provider\": \"openai\", \"modelShortName\": \"GPT-5\" }]" }
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
        guard
            let json = privacyConfigurationManager.privacyConfig.settings(for: iOSBrowserConfigSubfeature.onboardingFlowByDownloadReasonExperiment),
            let data = json.data(using: .utf8),
            let payload = try? JSONDecoder().decode(OnboardingAIModelsFallbackPayload.self, from: data),
            let response = payload.response,
            !response.models.isEmpty // If models is empty fallback to hardcoded version
        else {
            return nil
        }
        return response
    }
}

private struct OnboardingAIModelsFallbackPayload: Decodable {

    struct Model: Decodable {
        let id: String
        let provider: String
        let modelShortName: String?
    }

    let defaultModelId: String?
    let models: String

    /// `nil` when the encoded `models` string can't be decoded, so callers fall back to the baked default rather than surfacing an empty picker.
    var response: OnboardingAIModelResponse? {
        guard let decodedModels = try? JSONDecoder().decode([Model].self, from: Data(models.utf8)) else {
            return nil
        }
        let options = decodedModels.compactMap { model -> OnboardingAIModelOption? in
            guard let provider = OnboardingAIProvider(rawValue: model.provider) else { return nil }
            return OnboardingAIModelOption(id: model.id, provider: provider, modelShortName: model.modelShortName)
        }
        return OnboardingAIModelResponse(models: options, defaultModelId: defaultModelId)
    }
}
