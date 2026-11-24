//
//  WebPageTranslationSettings.swift
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

/// Remote config for web page translation, read from the top-level `pageTranslation` feature that
/// also gates the C-S-S script. Settings fall back to defaults when absent or malformed.
struct WebPageTranslationSettings {

    private enum Constants {
        static let sampleLengthKey = "sampleLength"
        static let defaultSampleLength = 4096
    }

    private let configManager: PrivacyConfigurationManaging

    init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.configManager = privacyConfigurationManager
    }

    /// How many characters of the page's text language detection reads (default 4096).
    var sampleLength: Int {
        guard let value = configManager.privacyConfig.settings(for: .pageTranslation)[Constants.sampleLengthKey] as? Int,
              value > 0 else {
            return Constants.defaultSampleLength
        }
        return value
    }

    /// False on sites in the feature's exceptions, the only per-site rule the C-S-S script follows:
    /// it runs without a config entry and on sites with protections off.
    func isEnabled(forDomain domain: String?) -> Bool {
        !configManager.privacyConfig.isInExceptionList(domain: domain, forFeature: .pageTranslation)
    }
}
