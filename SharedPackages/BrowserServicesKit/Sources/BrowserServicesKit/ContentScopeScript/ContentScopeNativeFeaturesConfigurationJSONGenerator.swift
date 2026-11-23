//
//  ContentScopeNativeFeaturesConfigurationJSONGenerator.swift
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

/// Adds features that native code owns to the configuration one content scope script receives.
///
/// Some content-scope features are not delivered by remote configuration: native code decides whether
/// they run and supplies their settings, for example per-process secrets. Each injected feature is
/// enabled with no exceptions and replaces any entry of the same name from the base configuration.
public struct ContentScopeNativeFeaturesConfigurationJSONGenerator: CustomisedPrivacyConfigurationJSONGenerating {

    let base: CustomisedPrivacyConfigurationJSONGenerating
    let fallbackConfiguration: Data?
    let features: [String: [String: Any]]

    /// - Parameters:
    ///   - base: The generator whose configuration is extended.
    ///   - fallbackConfiguration: Extended instead when `base` produces nothing, as the script would then use it.
    ///   - features: Settings for each injected feature, keyed by content-scope feature name. Values must be JSON types.
    public init(base: CustomisedPrivacyConfigurationJSONGenerating,
                fallbackConfiguration: Data? = nil,
                features: [String: [String: Any]]) {
        self.base = base
        self.fallbackConfiguration = fallbackConfiguration
        self.features = features
    }

    public var privacyConfiguration: Data? {
        let configuration = base.privacyConfiguration ?? fallbackConfiguration
        guard !features.isEmpty else { return configuration }

        // Native-owned features must not depend on remote configuration, so an unreadable one is replaced.
        var root = configuration.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            ?? ["features": [String: Any](), "unprotectedTemporary": [Any]()]
        var configuredFeatures = root["features"] as? [String: Any] ?? [:]
        for (name, settings) in features {
            configuredFeatures[name] = [
                "state": "enabled",
                "exceptions": [Any](),
                "settings": settings
            ]
        }
        root["features"] = configuredFeatures

        guard JSONSerialization.isValidJSONObject(root) else { return configuration }
        return try? JSONSerialization.data(withJSONObject: root)
    }
}
