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

import Foundation

/// A protocol that defines an interface for generating a JSON representation of a the privacy configuration file.
/// It can be used to create customised configurations
public protocol CustomisedPrivacyConfigurationJSONGenerating {
    var privacyConfiguration: Data? { get }
}

/// A JSON generator for content scope privacy configuration. This struct updates the configuration by enabling
/// privacy features for which the associated experiment cohort in ContentScopeExperiment  is `.treatment`.
///
/// Note: The subfeatures of ContentScopeExperiment must have the same name as the parent feature to be updated.
public struct ContentScopePrivacyConfigurationJSONGenerator: CustomisedPrivacyConfigurationJSONGenerating {
    let featureFlagger: FeatureFlagger
    let privacyConfigurationManager: PrivacyConfigurationManaging

    public init(featureFlagger: FeatureFlagger, privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    /// Generates and returns the updated privacy configuration as JSON data.
    ///
    /// This property attempts to parse the current configuration, update the feature states based on the experiment
    /// cohorts, and then serialize the updated configuration to JSON.
    public var privacyConfiguration: Data? {
        guard let config = try? PrivacyConfigurationData(data: privacyConfigurationManager.currentConfig) else { return nil }

        let newFeatures = updatedFeatureState(config: config.features)
        let newConfig = PrivacyConfigurationData(features: newFeatures, unprotectedTemporary: config.unprotectedTemporary, trackerAllowlist: config.trackerAllowlist, version: config.version)
        return try? newConfig.toJSONData()
    }

    /// Updates the feature states in the configuration based on the content scope experiments experiment cohorts.
    ///
    /// Iterates through all available content scope experiment feature flags and, if the resolved cohort for a feature is `.treatment`,
    /// updates the corresponding feature's state to "enabled". This relies on the assumption that the raw value of each experiment flag matches the feature name in the configuration.
    ///
    /// - Parameter config: A dictionary mapping feature names to their current privacy feature configuration.
    /// - Returns: A new dictionary with updated feature configurations.
    private func updatedFeatureState(config: [PrivacyConfigurationData.FeatureName: PrivacyConfigurationData.PrivacyFeature]) -> [PrivacyConfigurationData.FeatureName: PrivacyConfigurationData.PrivacyFeature] {
        var newConfig = config
        var configsToEnable = [ContentScopeExperimentsFeatureFlag]()
        for experiment in ContentScopeExperimentsFeatureFlag.allCases {
            if let cohort = featureFlagger.resolveCohort(for: experiment) as? ContentScopeExperimentsFeatureFlag.ContentScopeExperimentsCohort, cohort == .treatment {
                configsToEnable.append(experiment)
            }
        }

        for configToEnable in configsToEnable {
            if let oldConfig = config[configToEnable.rawValue] {
                newConfig[configToEnable.rawValue] = PrivacyConfigurationData.PrivacyFeature(
                    state: "enabled",
                    exceptions: oldConfig.exceptions,
                    settings: oldConfig.settings,
                    features: oldConfig.features,
                    minSupportedVersion: oldConfig.minSupportedVersion,
                    hash: oldConfig.hash
                )
            }
        }

        return newConfig
    }

}
