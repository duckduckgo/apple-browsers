//
//  DefaultBrowserPromptFeatureFlagAdapter.swift
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
import Core
import BrowserServicesKit
import SetDefaultBrowserCore

final class DefaultBrowserPromptFeatureFlagAdapter: DefaultBrowserPromptFeatureFlagProvider, DefaultBrowserPromptFeatureFlagSettingsProvider {

    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(featureFlagger: FeatureFlagger, privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    public var isDefaultBrowserPromptsFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(FeatureFlag.scheduledSetDefaultBrowserPrompts)
    }

    public var defaultBrowserPromptFeatureSettings: [String: Any] {
        privacyConfigurationManager.privacyConfig.settings(for: .setAsDefaultAndAddToDock)
    }
}
