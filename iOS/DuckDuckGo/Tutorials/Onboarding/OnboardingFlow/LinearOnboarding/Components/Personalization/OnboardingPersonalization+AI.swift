//
//  OnboardingPersonalization+AI.swift
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
import AIChat
import Onboarding
import Persistence

// MARK: - OnboardingAIChatPersonalizationStore

/// Store adapter backing the AI Chat feature toggles.
///
/// - `isDuckAIEnabled`  maps 1:1 onto
///   `isAIChatEnabled` / `enableAIChat(enable:)` — Keep Duck.ai On → `true`, Turn Duck.ai Off → `false`.
/// - `newTabTabToggleDefaultToAIChat` maps onto the Omnibar default mode:
///    - Open tabs with AI chat → `.duckAI`,
///    - Not Now → `.lastUsed` (the app default).
///
/// - See: [No AI: Setup step 2 (Duck.ai)](https://app.asana.com/1/137249556945/task/1216582276895643?focus=true)
/// - See: [AI Chat: Setup step 2 (NTP Default)](https://app.asana.com/1/137249556945/task/1216445221863471?focus=true)
extension AIChatSettings: OnboardingAIChatPersonalizationStore {

    var isDuckAIEnabled: Bool {
        get {
            isAIChatEnabled
        }
        set {
            enableAIChat(enable: newValue)
        }
    }
    
    var newTabTabToggleDefaultToAIChat: Bool {
        get {
            defaultOmnibarMode == .duckAI
        }
        set {
            let omnibarMode: DefaultOmnibarMode = newValue ? .duckAI : .lastUsed
            setDefaultOmnibarMode(omnibarMode)
        }
    }

}

// MARK: - OnboardingAIModelPersonalizationStore

/// Store adapter backing the **AI Chat model** picker on the first AI Chat onboarding step.
///
/// Persists the model id and short name in `AIChatPreferencesPersisting`, where Duck.ai reads them,
/// and the provider in the onboarding store. Setting `nil` clears all three.
///
/// - See: [AI Chat: Setup step 1](https://app.asana.com/1/137249556945/task/1216445221863466?focus=true)
final class OnboardingAIModelAdapter: OnboardingAIModelPersonalizationStore {
    private var persistor: AIChatPreferencesPersisting
    private let providerStore: any KeyedStoring<OnboardingAIModelStoringKeys>

    init(persistor: AIChatPreferencesPersisting, providerStore: any KeyedStoring<OnboardingAIModelStoringKeys> = UserDefaults.app.keyedStoring()) {
        self.persistor = persistor
        self.providerStore = providerStore
    }

    var selectedAIModel: OnboardingAIModel? {
        get {
            guard let id = persistor.selectedModelId else { return nil }
            // Best-effort name; the manager resolves the canonical name by matching `id`
            // against the fetched catalog, so only `id` needs to be correct here.
            return OnboardingAIModel(id: id, name: persistor.selectedModelShortName ?? "", provider: providerStore.selectedModelProvider)
        }
        set {
            persistor.selectedModelId = newValue?.id
            persistor.selectedModelShortName = newValue?.name
            providerStore.selectedModelProvider = newValue?.provider
        }
    }
}

private enum OnboardingAIModelStorageKeys: String, StorageKeyDescribing {
    case selectedModelProvider = "com-duckduckgo-onboarding-selectedAIModelProvider"
}

/// Onboarding-owned storage for the AI model picked during onboarding.
/// The model id and short name live in `AIChatPreferencesPersisting`, where Duck.ai reads them; only onboarding needs the provider.
struct OnboardingAIModelStoringKeys: StoringKeys {
    let selectedModelProvider = StorageKey<String>(OnboardingAIModelStorageKeys.selectedModelProvider)
}
