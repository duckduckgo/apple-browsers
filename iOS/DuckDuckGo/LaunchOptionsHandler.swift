//
//  LaunchOptionsHandler.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Core
import Foundation
import Persistence
import PrivacyConfig
import enum Common.DevicePlatform

public final class LaunchOptionsHandler {

    // Used by debug controller
    public static let isOnboardingCompleted = "isOnboardingCompleted"

    private static let appVariantName = "currentAppVariant"
    private static let automationPort = "automationPort"

    // MARK: - UI Test Override Constants

    /// Constants for UI test override launch parameters
    /// These allow Maestro tests to override feature flags, config rollouts, and experiments
    private enum UITestOverrides {
        /// Launch param format: ff.<featureFlagRawValue>=true/false
        /// Example: -ff.duckPlayer true
        static let featureFlagPrefix = "ff."

        /// Launch param format: config.rollout.<parentFeature>.<subfeature>=true/false
        /// Example: -config.rollout.duckPlayer.enableDuckPlayer true
        static let configRolloutPrefix = "config.rollout."

        /// Launch param format: experiment.<featureFlagRawValue>=<cohortID>
        /// Example: -experiment.onboardingSearchExperience control
        static let experimentCohortPrefix = "experiment."
    }

    private let environment: [String: String]
    private let userDefaults: UserDefaults
    private let arguments: [String]
    private var internalUserStore: InternalUserStoring

    private let isIpad: Bool
    private let systemVersion: String

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .app,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        internalUserStore: InternalUserStoring = InternalUserStore(),
        isIpad: Bool = DevicePlatform.isIpad,
        systemVersion: String = UIDevice.current.systemVersion
    ) {
        self.environment = environment
        self.userDefaults = userDefaults
        self.arguments = arguments
        self.internalUserStore = internalUserStore
        self.isIpad = isIpad
        self.systemVersion = systemVersion
    }

    public var onboardingStatus: OnboardingStatus {
        // Apple Issue affecting persistence storage on iPad 17.7.7
        // See: https://app.asana.com/1/137249556945/project/414709148257752/task/1210267814606214
        if isIpad && systemVersion == "17.7.7" {
            return .overridden(.developer(completed: true))
        }

        // If we're running UI Tests override onboarding settings permanently to keep state consistency across app launches. Some test re-launch the app within the same tests.
        // Launch Arguments can be read via userDefaults for easy value access.
        if let uiTestingOnboardingOverride = userDefaults.string(forKey: Self.isOnboardingCompleted) {
            return .overridden(.uiTests(completed: uiTestingOnboardingOverride == "true"))
        }

        // If developer override via Scheme Environment variable temporarily it means we want to show the onboarding.
        if let developerOnboardingOverride = environment["ONBOARDING"] {
            return .overridden(.developer(completed: developerOnboardingOverride == "false"))
        }

        return .notOverridden
    }

    public var automationPort: Int? {
        userDefaults.integer(forKey: Self.automationPort)
    }

#if DEBUG || ALPHA
    public func overrideOnboardingCompleted() {
        userDefaults.set("true", forKey: Self.isOnboardingCompleted)
    }
#endif

    public var appVariantName: String? {
        sanitisedEnvParameter(string: userDefaults.string(forKey: Self.appVariantName))
    }

    private func sanitisedEnvParameter(string: String?) -> String? {
        guard let string, string != "null" else { return nil }
        return string
    }
}

// MARK: - LaunchOptionsHandler + VariantManager

extension LaunchOptionsHandler: VariantNameOverriding {

    public var overriddenAppVariantName: String? {
        return appVariantName
    }

}


// MARK: - LaunchOptionsHandler + Onboarding

extension LaunchOptionsHandler {

    public enum OnboardingStatus: Equatable {
        case notOverridden
        case overridden(OverrideType)

        public enum OverrideType: Equatable {
            case developer(completed: Bool)
            case uiTests(completed: Bool)
        }

        public var isOverriddenCompleted: Bool {
            switch self {
            case .notOverridden:
                return false
            case .overridden(.developer(let completed)):
                return completed
            case .overridden(.uiTests(let completed)):
                return completed
            }
        }
    }

}

// MARK: - LaunchOptionsHandler + UI Test Overrides

extension LaunchOptionsHandler {

    /// Applies UI test overrides from launch arguments to the appropriate storage.
    ///
    /// This method reads launch arguments passed by Maestro and translates them into
    /// the UserDefaults keys that FeatureFlagger and PrivacyConfiguration expect.
    ///
    /// ## How it works
    /// iOS automatically stores launch arguments as key-value pairs in UserDefaults.
    /// When Maestro passes `"ff.myFlag": "true"`, iOS stores "true" under the key "ff.myFlag"
    /// in UserDefaults. We iterate `ProcessInfo.arguments` to discover which keys were passed,
    /// then read their values from UserDefaults.
    ///
    /// Internal user is only enabled if at least one override is applied.
    ///
    /// - Parameters:
    ///   - featureFlagOverrideStore: Store for feature flag and experiment overrides
    ///   - configRolloutStore: UserDefaults store for config rollout state
    public func applyUITestOverrides(
        featureFlagOverrideStore: KeyValueStoring,
        configRolloutStore: UserDefaults
    ) {
        let featureFlagPersistor = FeatureFlagLocalOverridesUserDefaultsPersistor(keyValueStore: featureFlagOverrideStore)
        var didApplyOverride = false

        for arg in arguments {
            guard arg.hasPrefix("-") else { continue }
            let key = String(arg.dropFirst()) // Remove leading "-"

            // Feature flag: ff.<flagName>
            // Read as string (same approach as experiment which works)
            if key.hasPrefix(UITestOverrides.featureFlagPrefix) {
                let flagName = String(key.dropFirst(UITestOverrides.featureFlagPrefix.count))
                if let flag = FeatureFlag(rawValue: flagName),
                   let stringValue = userDefaults.string(forKey: key) {
                    let enabled = stringValue.lowercased() == "true"
                    featureFlagPersistor.set(enabled, for: flag)
                    didApplyOverride = true
                }
            }

            // Config rollout: config.rollout.<path> -> config.<path>.enabled
            if key.hasPrefix(UITestOverrides.configRolloutPrefix) {
                let featurePath = String(key.dropFirst(UITestOverrides.configRolloutPrefix.count))
                if let stringValue = userDefaults.string(forKey: key) {
                    let enabled = stringValue.lowercased() == "true"
                    let targetKey = "config.\(featurePath).enabled"
                    configRolloutStore.set(enabled, forKey: targetKey)
                    didApplyOverride = true
                }
            }

            // Experiment: experiment.<flagName>
            if key.hasPrefix(UITestOverrides.experimentCohortPrefix) {
                let flagName = String(key.dropFirst(UITestOverrides.experimentCohortPrefix.count))
                if let flag = FeatureFlag(rawValue: flagName),
                   let cohortID = userDefaults.string(forKey: key), !cohortID.isEmpty {
                    featureFlagPersistor.setExperiment(cohortID, for: flag)
                    didApplyOverride = true
                }
            }
        }

        // Only enable internal user if we actually applied overrides
        if didApplyOverride {
            internalUserStore.isInternalUser = true
        }
    }
}
