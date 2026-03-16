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

import Common
import Foundation
import os.log
import PrivacyConfig

/// A protocol that defines an interface for generating a JSON representation of a the privacy configuration file.
/// It can be used to create customised configurations
public protocol CustomisedPrivacyConfigurationJSONGenerating {
    var privacyConfiguration: Data? { get }
}

/// A JSON generator for content scope privacy configuration.
///
/// Optionally injects tracker protection settings (tracker data, allowlist, unprotected domains,
/// CTL state) into the configuration for the C-S-S `trackerProtection` feature.
public struct ContentScopePrivacyConfigurationJSONGenerator: CustomisedPrivacyConfigurationJSONGenerating {
    let featureFlagger: FeatureFlagger
    let privacyConfigurationManager: PrivacyConfigurationManaging
    let trackerProtectionDataSource: TrackerProtectionDataSource?
    let ctlEnabled: Bool

    public init(featureFlagger: FeatureFlagger,
                privacyConfigurationManager: PrivacyConfigurationManaging,
                trackerProtectionDataSource: TrackerProtectionDataSource? = nil,
                ctlEnabled: Bool = false) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.trackerProtectionDataSource = trackerProtectionDataSource
        self.ctlEnabled = ctlEnabled
    }

    public var privacyConfiguration: Data? {
        guard let config = try? PrivacyConfigurationData(data: privacyConfigurationManager.currentConfig) else { return nil }

        var features = config.features

        if let dataSource = trackerProtectionDataSource {
            features = injectTrackerProtectionSettings(into: features, from: dataSource)
        }

        let newConfig = PrivacyConfigurationData(features: features, unprotectedTemporary: config.unprotectedTemporary, trackerAllowlist: config.trackerAllowlist, version: config.version)
        return try? newConfig.toJSONData(
            excludeFeatures: [
                PrivacyConfigurationData.CodingKeys.trackerAllowlist.rawValue,
                PrivacyFeature.autoconsent.rawValue
            ]
        )
    }

    private func injectTrackerProtectionSettings(into features: [String: PrivacyConfigurationData.PrivacyFeature],
                                                 from _: TrackerProtectionDataSource) -> [String: PrivacyConfigurationData.PrivacyFeature] {
        var mutableFeatures = features

        let existingFeature = mutableFeatures["trackerProtection"]
        var settings: [String: Any] = existingFeature?.settings ?? [:]

        // trackerData is now passed via ContentScopeProperties (args.trackerData),
        // not via feature settings. See ContentScopeUserScript.swift.

        let privacyConfig = privacyConfigurationManager.privacyConfig

        var allowlistDict: [String: [[String: Any]]] = [:]
        for (domain, entries) in privacyConfig.trackerAllowlist.entries {
            allowlistDict[domain] = entries.map { entry in
                ["rule": entry.rule.escapedForRegex(), "domains": entry.domains]
            }
        }
        settings["allowlist"] = allowlistDict

        settings["tempUnprotectedDomains"] = privacyConfig.tempUnprotectedDomains
        settings["userUnprotectedDomains"] = privacyConfig.userUnprotectedDomains
        settings["contentBlockingExceptions"] = privacyConfig.exceptionsList(forFeature: .contentBlocking)
        settings["blockingEnabled"] = privacyConfig.isEnabled(featureKey: .contentBlocking)
        settings["ctlEnabled"] = ctlEnabled

        let trackerProtectionFeature = PrivacyConfigurationData.PrivacyFeature(
            state: existingFeature?.state ?? "enabled",
            exceptions: existingFeature?.exceptions ?? [],
            settings: settings,
            minSupportedVersion: existingFeature?.minSupportedVersion,
            hash: existingFeature?.hash
        )

        mutableFeatures["trackerProtection"] = trackerProtectionFeature
        return mutableFeatures
    }
}

// MARK: - Private Helpers

private extension String {
    /// Escapes regex special characters for use in JavaScript's String.match().
    ///
    /// C-S-S allowlist rules are passed to JavaScript's `.match()` method which treats
    /// the string as a regex pattern. This function escapes special characters to ensure
    /// literal matching (e.g., dots match literal dots, not wildcards).
    func escapedForRegex() -> String {
        // Regex special characters that need escaping: . \ + * ? [ ] ^ $ ( ) { } = ! < > | : -
        let specialChars = ["\\", ".", "+", "*", "?", "[", "]", "^", "$", "(", ")", "{", "}", "=", "!", "<", ">", "|", ":", "-"]
        var escaped = self
        for char in specialChars {
            escaped = escaped.replacingOccurrences(of: char, with: "\\\(char)")
        }
        return escaped
    }
}
