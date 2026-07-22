//
//  SearchTokenExperimentSettings.swift
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

/// Remotely-configured tuning for the Search Token experiment, read from the `searchTokenExperiment`
/// subfeature settings. Falls back to defaults when the setting is absent or malformed.
struct SearchTokenExperimentSettings {

    private enum Constants {
        static let defaultTokenTTL: TimeInterval = 300
        static let defaultRefreshWindow: TimeInterval = 120
        static let tokenTTLKey = "tokenTTLSeconds"
        static let refreshWindowKey = "refreshWindowSeconds"
    }

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    /// Token lifetime in seconds (default 300).
    var tokenTTL: TimeInterval {
        seconds(forKey: Constants.tokenTTLKey) ?? Constants.defaultTokenTTL
    }

    /// Refresh-ahead window in seconds (default 120). Should be `< tokenTTL`.
    var refreshWindow: TimeInterval {
        seconds(forKey: Constants.refreshWindowKey) ?? Constants.defaultRefreshWindow
    }

    private func seconds(forKey key: String) -> TimeInterval? {
        guard let json = privacyConfigurationManager.privacyConfig.settings(for: iOSBrowserConfigSubfeature.searchTokenExperiment),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dict[key] as? NSNumber else {
            return nil
        }
        return value.doubleValue
    }
}
