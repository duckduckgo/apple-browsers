//
//  PrivacyConfigurationData.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public struct PrivacyConfigurationData {

    public typealias FeatureName = String
    public typealias TrackerAllowlistData = [String: [TrackerAllowlist.Entry]]

    enum CodingKeys: String {
        case features
        case unprotectedTemporary
        case trackerAllowlist
        case version
    }

    public struct State {
        static public let disabled = "disabled"
        static public let `internal` = "internal"
        static public let enabled = "enabled"
    }

    public struct Cohort {
        public let name: String
        public let weight: Int

        enum CodingKeys: String {
            case name
            case weight
        }

        public init?(json: [String: Any]) {
            guard let name = json[CodingKeys.name.rawValue] as? String,
                  let weight = json[CodingKeys.weight.rawValue] as? Int else {
                return nil
            }

            self.name = name
            self.weight = weight
        }
    }
    public let features: [FeatureName: PrivacyFeature]
    public let trackerAllowlist: TrackerAllowlist
    public let unprotectedTemporary: [ExceptionEntry]
    public let version: String?

    public init(data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw PrivacyConfigurationManager.ParsingError.dataMismatch
        }
        self = .init(json: json)
    }

    internal init(json: [String: Any]) {

        if let versionInt = json[CodingKeys.version.rawValue] as? Int {
            version = String(versionInt)
        } else {
            version = json[CodingKeys.version.rawValue] as? String
        }

        if let tempListData = json[CodingKeys.unprotectedTemporary.rawValue] as? [[String: String]] {
            unprotectedTemporary = tempListData.compactMap({ ExceptionEntry(json: $0) })
        } else {
            unprotectedTemporary = []
        }

        if var featuresData = json[CodingKeys.features.rawValue] as? [String: Any] {
            var features = [FeatureName: PrivacyFeature]()

            // Allowlist entry does not follow the usual feature structure - process it first
            if let allowlistEntry = featuresData[CodingKeys.trackerAllowlist.rawValue] as? [String: Any] {
                if let allowlist = TrackerAllowlist(json: allowlistEntry) {
                    self.trackerAllowlist = allowlist
                } else {
                    self.trackerAllowlist = TrackerAllowlist(entries: [:], state: State.disabled)
                }
                featuresData.removeValue(forKey: CodingKeys.trackerAllowlist.rawValue)
            } else {
                self.trackerAllowlist = TrackerAllowlist(entries: [:], state: State.disabled)
            }

            for featureEntry in featuresData {

                guard let featureData = featureEntry.value as? [String: Any],
                      let feature = PrivacyFeature(json: featureData) else { continue }
                features[featureEntry.key] = feature
            }
            self.features = features
        } else {
            self.features = [:]
            self.trackerAllowlist = TrackerAllowlist(entries: [:], state: State.disabled)
        }
    }

    public init(features: [FeatureName: PrivacyFeature],
                unprotectedTemporary: [ExceptionEntry],
                trackerAllowlist: TrackerAllowlistData,
                version: String? = nil) {
        self.features = features
        self.unprotectedTemporary = unprotectedTemporary
        self.trackerAllowlist = TrackerAllowlist(entries: trackerAllowlist, state: State.enabled)
        self.version = version
    }

    public init(features: [FeatureName: PrivacyFeature],
                unprotectedTemporary: [ExceptionEntry],
                trackerAllowlist: TrackerAllowlist,
                version: String? = nil) {
        self.features = features
        self.unprotectedTemporary = unprotectedTemporary
        self.trackerAllowlist = trackerAllowlist
        self.version = version
    }

    public class PrivacyFeature {
        public typealias FeatureState = String
        public typealias ExceptionList = [ExceptionEntry]
        public typealias FeatureSettings = [String: Any]
        public typealias Features = [String: Feature]
        public typealias FeatureSupportedVersion = String
        public typealias SubfeatureSettings = String

        enum CodingKeys: String {
            case state
            case exceptions
            case settings
            case features
            case minSupportedVersion
            case hash
        }

        public struct Feature {
            enum CodingKeys: String {
                case state
                case minSupportedVersion
                case rollout
                case cohorts
                case targets
                case settings
            }

            public struct Rollout: Hashable {
                enum CodingKeys: String {
                    case steps
                }

                public let steps: [RolloutStep]

                public init(json: [String: Any]) {
                    var rolloutSteps = [RolloutStep]()
                    if let steps = json[CodingKeys.steps.rawValue] as? [[String: Any]] {
                        for step in steps {
                            rolloutSteps.append(RolloutStep(json: step))
                        }
                    }

                    self.steps = rolloutSteps
                }
            }

            public struct RolloutStep: Hashable {
                enum CodingKeys: String {
                    case percent
                }

                public let percent: Double

                public init(json: [String: Any]) {
                    self.percent = json[CodingKeys.percent.rawValue] as? Double ?? 0
                }
            }

            public struct Target {
                enum CodingKeys: String {
                    case localeCountry
                    case localeLanguage
                }

                public let localeCountry: String?
                public let localeLanguage: String?

                public init(json: [String: Any]) {
                    self.localeCountry = json[CodingKeys.localeCountry.rawValue] as? String
                    self.localeLanguage = json[CodingKeys.localeLanguage.rawValue] as? String
                }
            }

            public let state: FeatureState
            public let minSupportedVersion: FeatureSupportedVersion?
            public let rollout: Rollout?
            public let cohorts: [Cohort]?
            public let targets: [Target]?
            public let settings: SubfeatureSettings?

            public init?(json: [String: Any]) {
                guard let state = json[CodingKeys.state.rawValue] as? String else {
                    return nil
                }

                self.state = state
                self.minSupportedVersion = json[CodingKeys.minSupportedVersion.rawValue] as? String

                if let rollout = json[CodingKeys.rollout.rawValue] as? [String: Any] {
                    self.rollout = Rollout(json: rollout)
                } else {
                    self.rollout = nil
                }

                if let cohortData = json[CodingKeys.cohorts.rawValue] as? [[String: Any]] {
                    let parsedCohorts = cohortData.compactMap { Cohort(json: $0) }
                    cohorts = parsedCohorts.isEmpty ? nil : parsedCohorts
                } else {
                    cohorts = nil
                }

                if let targetData = json[CodingKeys.targets.rawValue] as? [[String: Any]] {
                    targets = targetData.compactMap { Target(json: $0) }
                } else {
                    targets = nil
                }

                if let settingsData = json[CodingKeys.settings.rawValue] {
                    let jsonData = try? JSONSerialization.data(withJSONObject: settingsData, options: [])
                    settings = jsonData != nil ? String(data: jsonData!, encoding: .utf8) : nil
                } else {
                    settings = nil
                }
            }
        }

        public let state: FeatureState
        public let exceptions: ExceptionList
        public let settings: FeatureSettings
        public let features: Features
        public let minSupportedVersion: FeatureSupportedVersion?
        public let hash: String?

        public init?(json: [String: Any]) {
            guard let state = json[CodingKeys.state.rawValue] as? String else { return nil }
            self.state = state

            if let exceptionsData = json[CodingKeys.exceptions.rawValue] as? [[String: String]] {
                self.exceptions = exceptionsData.compactMap({ ExceptionEntry(json: $0) })
            } else {
                self.exceptions = []
            }

            self.settings = (json[CodingKeys.settings.rawValue] as? [String: Any]) ?? [:]

            var features = [String: Feature]()
            if let featuresDict = json[CodingKeys.features.rawValue] as? [String: [String: Any]] {
                for (key, value) in featuresDict {
                    features[key] = Feature(json: value)
                }
            }
            self.features = features
            self.minSupportedVersion = json[CodingKeys.minSupportedVersion.rawValue] as? String
            self.hash = json[CodingKeys.hash.rawValue] as? String
        }

        public init(state: FeatureState,
                    exceptions: [ExceptionEntry],
                    settings: [String: Any] = [:],
                    features: Features = [:],
                    minSupportedVersion: String? = nil,
                    hash: String? = nil) {
            self.state = state
            self.exceptions = exceptions
            self.settings = settings
            self.minSupportedVersion = minSupportedVersion
            self.features = features
            self.hash = hash
        }
    }

    public class TrackerAllowlist: PrivacyFeature {

        public struct Entry: Encodable {

            public let rule: String
            public let domains: [String]

            public init(rule: String, domains: [String]) {
                self.rule = rule
                self.domains = domains
            }
        }

        public private(set) var entries: TrackerAllowlistData

        public override init?(json: [String: Any]) {
            self.entries = [:]
            super.init(json: json)

            guard self.state != State.disabled else { return }

            var entries = [String: [Entry]]()

            let settings = (json[PrivacyFeature.CodingKeys.settings.rawValue] as? [String: Any]) ?? [:]

            if let trackers = settings["allowlistedTrackers"] as? [String: [String: [Any]]] {
                for (trackerDomain, trackerRules) in trackers {
                    if let rules = trackerRules["rules"] as? [ [String: Any] ] {
                        entries[trackerDomain] = rules.compactMap { ruleDict -> Entry? in
                            guard let rule = ruleDict["rule"] as? String, let domains = ruleDict["domains"] as? [String] else { return nil }

                            return Entry(rule: rule, domains: domains)
                        }
                    }
                }
            }

            self.entries = entries
        }

        public init(entries: [String: [Entry]], state: FeatureState) {
            self.entries = entries

            super.init(state: state, exceptions: [])
        }
    }

    public struct ExceptionEntry {
        public typealias ExcludedDomain = String
        public typealias ExclusionReason = String

        enum CodingKeys: String {
            case domain
            case reason
        }

        public let domain: ExcludedDomain
        public let reason: ExclusionReason?

        public init?(json: [String: String]) {
            guard let domain = json[CodingKeys.domain.rawValue] else { return nil }
            self.init(domain: domain, reason: json[CodingKeys.reason.rawValue])
        }

        public init(domain: String, reason: String?) {
            self.domain = domain
            self.reason = reason
        }
    }
}

// MARK: Encoding Functions
extension PrivacyConfigurationData {
    /// Returns a dictionary representation of the configuration.
    ///
    /// - Parameters:
    ///   - excludeFeatures: defines a list of keys from the `features` sub-object
    ///                      that will be skipped and not present in the resulting dictionary.
    ///
    public func toJSONDictionary(excludeFeatures: [String] = []) -> [String: Any] {
        var json = [String: Any]()

        if let version = self.version {
            json[CodingKeys.version.rawValue] = Int(version) ?? version
        }

        json[CodingKeys.unprotectedTemporary.rawValue] = self.unprotectedTemporary.map { $0.toJSONDictionary() }

        var featuresDict = [String: Any]()
        if !excludeFeatures.contains(CodingKeys.trackerAllowlist.rawValue), let allowlistJSON = trackerAllowlist.toTrackerAllowListJSONDictionary() {
            featuresDict[CodingKeys.trackerAllowlist.rawValue] = allowlistJSON
        }
        for (key, feature) in features where !excludeFeatures.contains(key) {
            if let featureJSON = feature.toJSONDictionary() {
                featuresDict[key] = featureJSON
            }
        }
        json[CodingKeys.features.rawValue] = featuresDict

        return json
    }

    /// Returns the JSON Data representation.
    ///
    /// - Parameters:
    ///   - excludeFeatures: defines a list of keys from the `features` sub-object
    ///                      that will be skipped and not present in the resulting dictionary.
    ///
    public func toJSONData(excludeFeatures: [String] = []) throws -> Data {
        let jsonDict = self.toJSONDictionary(excludeFeatures: excludeFeatures)
        return try JSONSerialization.data(withJSONObject: jsonDict, options: [])
    }
}

extension PrivacyConfigurationData.ExceptionEntry {
    public func toJSONDictionary() -> [String: String] {
        var dict: [String: String] = [CodingKeys.domain.rawValue: domain]
        if let reason = reason {
            dict[CodingKeys.reason.rawValue] = reason
        }
        return dict
    }
}

extension PrivacyConfigurationData.PrivacyFeature {
    public func toJSONDictionary() -> [String: Any]? {
        var dict: [String: Any] = [:]
        dict[CodingKeys.state.rawValue] = state
        dict[CodingKeys.exceptions.rawValue] = exceptions.map { $0.toJSONDictionary() }
        if !settings.isEmpty {
            dict[CodingKeys.settings.rawValue] = settings
        }

        var featuresDict = [String: Any]()
        for (key, feature) in features {
            if let featureJSON = feature.toJSONDictionary() {
                featuresDict[key] = featureJSON
            }
        }
        if !featuresDict.isEmpty {
            dict[CodingKeys.features.rawValue] = featuresDict
        }

        if let minVersion = minSupportedVersion {
            dict[CodingKeys.minSupportedVersion.rawValue] = minVersion
        }
        if let hash = hash {
            dict[CodingKeys.hash.rawValue] = hash
        }
        return dict
    }
}

extension PrivacyConfigurationData.PrivacyFeature.Feature {
    public func toJSONDictionary() -> [String: Any]? {
        var dict: [String: Any] = [:]
        dict[CodingKeys.state.rawValue] = state
        if let minVersion = minSupportedVersion {
            dict[CodingKeys.minSupportedVersion.rawValue] = minVersion
        }
        if let rollout = rollout?.toJSONDictionary() {
            dict[CodingKeys.rollout.rawValue] = rollout
        }
        if let cohorts = cohorts {
            dict[CodingKeys.cohorts.rawValue] = cohorts.map { $0.toJSONDictionary() }
        }
        if let targets = targets {
            dict[CodingKeys.targets.rawValue] = targets.map { $0.toJSONDictionary() }
        }
        if let settings = settings {
            // Attempt to convert the settings JSON string back to an object
            if let settingsData = settings.data(using: .utf8),
               let settingsObject = try? JSONSerialization.jsonObject(with: settingsData, options: []) {
                dict[CodingKeys.settings.rawValue] = settingsObject
            } else {
                dict[CodingKeys.settings.rawValue] = settings
            }
        }
        return dict
    }
}

extension PrivacyConfigurationData.PrivacyFeature.Feature.Rollout {
    public func toJSONDictionary() -> [String: Any] {
        return [CodingKeys.steps.rawValue: steps.map { $0.toJSONDictionary() }]
    }
}

extension PrivacyConfigurationData.PrivacyFeature.Feature.RolloutStep {
    public func toJSONDictionary() -> [String: Any] {
        return [CodingKeys.percent.rawValue: percent]
    }
}

extension PrivacyConfigurationData.PrivacyFeature.Feature.Target {
    public func toJSONDictionary() -> [String: Any] {
        var dict = [String: Any]()
        if let country = localeCountry {
            dict[CodingKeys.localeCountry.rawValue] = country
        }
        if let language = localeLanguage {
            dict[CodingKeys.localeLanguage.rawValue] = language
        }
        return dict
    }
}

extension PrivacyConfigurationData.Cohort {
    public func toJSONDictionary() -> [String: Any] {
        return [CodingKeys.name.rawValue: name, CodingKeys.weight.rawValue: weight]
    }
}

extension PrivacyConfigurationData.TrackerAllowlist {
    func toTrackerAllowListJSONDictionary() -> [String: Any]? {
        guard var baseDict = self.toJSONDictionary() else { return nil }

        var allowlistedTrackers = [String: Any]()
        for (trackerDomain, entries) in entries {
            let rules = entries.map { entry -> [String: Any] in
                return ["rule": entry.rule, "domains": entry.domains]
            }
            allowlistedTrackers[trackerDomain] = ["rules": rules]
        }

        // Insert the allowlistedTrackers into the base dictionary's settings.
        baseDict[PrivacyConfigurationData.PrivacyFeature.CodingKeys.settings.rawValue] = ["allowlistedTrackers": allowlistedTrackers]
        return baseDict
    }
}
