//
//  ContentScopePrivacyConfigurationJSONGenerator.swift
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

import PrivacyConfig
import Foundation

/// A protocol that defines an interface for generating a JSON representation of a the privacy configuration file.
/// It can be used to create customised configurations
public protocol CustomisedPrivacyConfigurationJSONGenerating {
    var privacyConfiguration: Data? { get }
}

/// A JSON generator for content scope privacy configuration.
public struct ContentScopePrivacyConfigurationJSONGenerator: CustomisedPrivacyConfigurationJSONGenerating {
    let featureFlagger: FeatureFlagger
    let privacyConfigurationManager: PrivacyConfigurationManaging
    let excludedFeatures: [String]
    let isSurrogateInjectionDisabled: () -> Bool

    /// Features every caller keeps out of the injected configuration. Exposed so a caller that
    /// needs to exclude more can extend this rather than restate it and drift.
    public static let defaultExcludedFeatures = [
        PrivacyConfigurationData.CodingKeys.trackerAllowlist.rawValue,
        PrivacyFeature.autoconsent.rawValue,
        PrivacyFeature.eventHub.rawValue
    ]

    /// - Parameter isSurrogateInjectionDisabled: When it returns `true`, the generated configuration sets
    ///   `trackerProtection.settings.surrogateInjection` to `disabled`, so content-scope-scripts stops injecting
    ///   surrogates but still reports resource loads. Used when the embedded web extension serves surrogates instead.
    public init(featureFlagger: FeatureFlagger,
                privacyConfigurationManager: PrivacyConfigurationManaging,
                excludedFeatures: [String] = Self.defaultExcludedFeatures,
                isSurrogateInjectionDisabled: @escaping () -> Bool = { false }) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.excludedFeatures = excludedFeatures
        self.isSurrogateInjectionDisabled = isSurrogateInjectionDisabled
    }

    public var privacyConfiguration: Data? {
        let configuration = privacyConfigurationManager.currentConfigJSON(excludingFeatures: excludedFeatures)
        guard let configuration, isSurrogateInjectionDisabled() else { return configuration }
        return Self.disablingSurrogateInjection(in: configuration) ?? configuration
    }

    /// Returns `configuration` with `features.trackerProtection.settings.surrogateInjection` set to `disabled`,
    /// or `nil` if the configuration isn't a JSON object.
    static func disablingSurrogateInjection(in configuration: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: configuration)) as? [String: Any] else { return nil }

        let featureKey = PrivacyFeature.trackerProtection.rawValue
        var features = root["features"] as? [String: Any] ?? [:]
        var trackerProtection = features[featureKey] as? [String: Any] ?? [:]
        var settings = trackerProtection["settings"] as? [String: Any] ?? [:]
        settings[Constants.surrogateInjectionSettingKey] = PrivacyConfigurationData.State.disabled
        trackerProtection["settings"] = settings
        features[featureKey] = trackerProtection
        root["features"] = features

        return try? JSONSerialization.data(withJSONObject: root)
    }

    enum Constants {
        static let surrogateInjectionSettingKey = "surrogateInjection"
    }

}
