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

    /// Features every caller keeps out of the injected configuration. Exposed so a caller that
    /// needs to exclude more can extend this rather than restate it and drift.
    public static let defaultExcludedFeatures = [
        PrivacyConfigurationData.CodingKeys.trackerAllowlist.rawValue,
        PrivacyFeature.autoconsent.rawValue,
        PrivacyFeature.eventHub.rawValue
    ]

    public init(featureFlagger: FeatureFlagger,
                privacyConfigurationManager: PrivacyConfigurationManaging,
                excludedFeatures: [String] = Self.defaultExcludedFeatures) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.excludedFeatures = excludedFeatures
    }

    /// Every tab builds two content scope scripts, and each used to parse and re-encode the full
    /// privacy config on the main thread. The output only depends on the raw config and the
    /// excluded features, so it's computed once per config version and exclusion set.
    public var privacyConfiguration: Data? {
        let currentConfig = privacyConfigurationManager.currentConfig
        if let cached = Self.cache.value(for: currentConfig, excludedFeatures: excludedFeatures) {
            return cached
        }

        guard let config = try? PrivacyConfigurationData(data: currentConfig) else { return nil }

        let newConfig = PrivacyConfigurationData(features: config.features, unprotectedTemporary: config.unprotectedTemporary, trackerAllowlist: config.trackerAllowlist, version: config.version)
        guard let json = try? newConfig.toJSONData(excludeFeatures: excludedFeatures) else { return nil }

        Self.cache.store(json, for: currentConfig, excludedFeatures: excludedFeatures)
        return json
    }

    static let cache = GeneratedConfigCache()

}

/// Keeps the latest generated JSON for each exclusion set. A new config replaces the entry, so the
/// cache holds one entry per distinct exclusion set (a handful per app).
final class GeneratedConfigCache: @unchecked Sendable {

    private struct Entry {
        let sourceConfig: Data
        let json: Data
    }

    private let lock = NSLock()
    private var entries: [[String]: Entry] = [:]

    func value(for sourceConfig: Data, excludedFeatures: [String]) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[excludedFeatures], entry.sourceConfig == sourceConfig else { return nil }
        return entry.json
    }

    func store(_ json: Data, for sourceConfig: Data, excludedFeatures: [String]) {
        lock.lock()
        defer { lock.unlock() }
        entries[excludedFeatures] = Entry(sourceConfig: sourceConfig, json: json)
    }

}
