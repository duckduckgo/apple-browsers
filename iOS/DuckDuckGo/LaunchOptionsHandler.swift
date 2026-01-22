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

import Foundation
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

        /// The UserDefaults key used by InternalUserStore to track internal user status
        static let internalUserStoreKey = "com.duckduckgo.app.featureFlaggingDidVerifyInternalUser.v2"
    }

    private let environment: [String: String]
    private let userDefaults: UserDefaults

    private let isIpad: Bool
    private let systemVersion: String

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .app,
        isIpad: Bool = DevicePlatform.isIpad,
        systemVersion: String = UIDevice.current.systemVersion
    ) {
        self.environment = environment
        self.userDefaults = userDefaults
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

    /// Applies all parsed overrides to the appropriate storage.
    ///
    /// - Parameters:
    ///   - featureFlagOverrideStore: UserDefaults store for feature flag overrides
    ///   - configRolloutStore: UserDefaults store for config rollout state
    public func applyUITestOverrides(
        featureFlagOverrideStore: UserDefaults,
        configRolloutStore: UserDefaults
    ) {
        guard ProcessInfo.isRunningUITests else { return }

        // Always enable internal user for UI tests (required for feature flag overrides)
        UserDefaults.standard.set(true, forKey: UITestOverrides.internalUserStoreKey)

        // Find all launch argument keys by looking at ProcessInfo.arguments
        // Arguments come as pairs: ["-key", "value", "-key2", "value2", ...]
        let args = ProcessInfo.processInfo.arguments

        for arg in args {
            guard arg.hasPrefix("-") else { continue }
            let key = String(arg.dropFirst()) // Remove leading "-"

            // Feature flag: ff.<flagName> -> localOverride<FlagName>
            if key.hasPrefix(UITestOverrides.featureFlagPrefix) {
                let flagName = String(key.dropFirst(UITestOverrides.featureFlagPrefix.count))
                if let value = userDefaults.string(forKey: key) {
                    let enabled = value.lowercased() == "true"
                    let targetKey = "localOverride\(flagName.capitalizedFirstLetter)"
                    featureFlagOverrideStore.set(enabled, forKey: targetKey)
                }
            }
            
            // Config rollout: config.rollout.<path> -> config.<path>.enabled
            if key.hasPrefix(UITestOverrides.configRolloutPrefix) {
                let featurePath = String(key.dropFirst(UITestOverrides.configRolloutPrefix.count))
                if let value = userDefaults.string(forKey: key) {
                    let enabled = value.lowercased() == "true"
                    let targetKey = "config.\(featurePath).enabled"
                    configRolloutStore.set(enabled, forKey: targetKey)
                }
            }
            
            // Experiment: experiment.<flagName> -> localOverride<FlagName>_cohort
            if key.hasPrefix(UITestOverrides.experimentCohortPrefix) {
                let flagName = String(key.dropFirst(UITestOverrides.experimentCohortPrefix.count))
                if let cohortID = userDefaults.string(forKey: key), !cohortID.isEmpty {
                    let targetKey = "localOverride\(flagName.capitalizedFirstLetter)_cohort"
                    featureFlagOverrideStore.set(cohortID, forKey: targetKey)
                }
            }
        }
    }
}

// MARK: - String Extension

private extension String {
    var capitalizedFirstLetter: String {
        return prefix(1).capitalized + dropFirst()
    }
}

// MARK: - ProcessInfo Extension

extension ProcessInfo {
    static var isRunningUITests: Bool {
        // Maestro can pass arguments as either type depending on YAML formatting
        if let stringValue = UserDefaults.standard.string(forKey: "isRunningUITests") {
            return stringValue.lowercased() == "true"
        }
        if UserDefaults.standard.object(forKey: "isRunningUITests") != nil {
            return UserDefaults.standard.bool(forKey: "isRunningUITests")
        }
        // Fallback to checking process arguments (for XCUITest or direct argument passing)
        return processInfo.arguments.contains("isRunningUITests")
    }
}
