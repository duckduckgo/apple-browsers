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
import FeatureFlags_iOS

/// Remotely-configured tuning for web page translation, read from the `webPageTranslation`
/// subfeature settings. Falls back to defaults when the setting is absent or malformed.
struct WebPageTranslationSettings {

    private enum Constants {
        static let defaultSampleLength = 4096
    }

    /// The settings JSON; every field is optional so a missing one falls back on its own.
    private struct RemoteSettings: Decodable {
        let sampleLength: Int?
    }

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    /// How many characters of the page's text language detection reads (default 4096).
    var sampleLength: Int {
        guard let json = privacyConfigurationManager.privacyConfig.settings(for: iOSBrowserConfigSubfeature.webPageTranslation),
              let settings = try? JSONDecoder().decode(RemoteSettings.self, from: Data(json.utf8)),
              let value = settings.sampleLength,
              value > 0 else {
            return Constants.defaultSampleLength
        }
        return value
    }
}
