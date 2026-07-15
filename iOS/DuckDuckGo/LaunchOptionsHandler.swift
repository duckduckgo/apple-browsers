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
import Persistence
import PrivacyConfig
import Common
import FoundationExtensions

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
        /// Example: -experiment.someExperimentFlag treatmentA
        static let experimentCohortPrefix = "experiment."

        static let internalUserKey = "isInternalUser"
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

    /// Returns the automation port if set, nil otherwise.
    /// Port must be in the valid UInt16 range (1-65535).
    public var automationPort: Int? {
        let port = userDefaults.integer(forKey: Self.automationPort)
        guard UInt16(exactly: port) != nil, port > 0 else { return nil }
        return port
    }

    /// Returns true if the app is running in any automation mode (WebDriver or UI Tests)
    public var isAutomationSession: Bool {
#if DEBUG || ALPHA
        isWebDriverAutomationSession || isUITesting
#else
        isUITesting
#endif
    }

    /// Returns true only when WebDriver automation is active.
    public var isWebDriverAutomationSession: Bool {
#if DEBUG || ALPHA
        AutomationSession.isWebDriverActive(automationPort: automationPort)
#else
        false
#endif
    }

    public var isUITesting: Bool {
        environment["UITEST_MODE"] == "1" ||
        environment["UITEST_MODE_ONBOARDING"] == "1" ||
        arguments.contains("isRunningUITests") ||
        userDefaults.string(forKey: "isRunningUITests") == "true"
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
    /// Internal user mode is only enabled when `-isInternalUser true` is explicitly passed.
    /// Other overrides (ff., config.rollout., experiment.) are honored by `FeatureFlagger` in
    /// UI test mode without forcing internal user (configured in `AppDependencyProvider`).
    ///
    /// - Parameters:
    ///   - featureFlagOverrideStore: Store for feature flag and experiment overrides
    ///   - configRolloutStore: UserDefaults store for config rollout state
    public func applyUITestOverrides(
        featureFlagOverrideStore: KeyValueStoring,
        configRolloutStore: UserDefaults
    ) {
        // Read the group-ID prefix once; used for suite-namespaced stores.
        let groupIdPrefix = Bundle.main.object(forInfoDictionaryKey: "DuckDuckGoGroupIdentifierPrefix") as? String

        if arguments.contains("-clearAllDefaults") {
            clearAllDefaults(groupIdPrefix: groupIdPrefix)
        }

        if arguments.contains("-backdateInstallDate") {
            backdateInstallDate(groupIdPrefix: groupIdPrefix)
        }

        // Writing ATB keys in -backdateInstallDate makes hasInstallStatistics=true, which causes
        // assignVariantIfNeeded to return early without calling onVariantAssigned → primeForUse()
        // is never called → isDismissed stays true (its default) → contextual dax dialogs are
        // suppressed. Pass -setDaxNotDismissed to explicitly opt in to contextual dax dialogs.
        if arguments.contains("-setDaxNotDismissed") {
            userDefaults.set(false, forKey: "com.duckduckgo.ios.daxOnboardingIsDismissed")
        }

        // Dax state overrides — used by upgrade-path tests to simulate pre-feature-build UserDefaults.
        if arguments.contains("-setDaxState.browsingFinalDialogShown") {
            userDefaults.set(true, forKey: "com.duckduckgo.ios.daxOnboardingFinalDialogSeen")
        }

        applyFlagOverrides(featureFlagOverrideStore: featureFlagOverrideStore, configRolloutStore: configRolloutStore)
    }

    // MARK: - State reset helpers

    /// Wipes all persistent state so the test run starts with a clean slate.
    /// Must be called before feature-flag overrides are written.
    private func clearAllDefaults(groupIdPrefix: String?) {
        if let bundleID = Bundle.main.bundleIdentifier {
            userDefaults.removePersistentDomain(forName: bundleID)
        }
        if let prefix = groupIdPrefix {
            let suite = "\(prefix).statistics"
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        clearAppSupportFiles()
    }

    private func clearAppSupportFiles() {
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let fm = FileManager.default

        // PromptCooldownKeyValueFilesStore — must be removed before AppKeyValueFileStoreService
        // opens the file and acquires its lock.
        try? fm.removeItem(at: appSupportDir.appendingPathComponent("AppKeyValueStore"))

        // Tab model — KeyValueFileStore files written by TabsModelPersistence.
        // Without these the app restores the previous browsing session on relaunch.
        try? fm.removeItem(at: appSupportDir.appendingPathComponent("TabsModel"))
        try? fm.removeItem(at: appSupportDir.appendingPathComponent("FireTabsModel"))

        // WebKit per-tab interaction state (scroll position, form data, WKWebView session).
        // Stored under <AppSupport>/<BundleID>/webview-interaction/ by TabInteractionStateDiskSource.
        if let bundleID = Bundle.main.bundleIdentifier {
            try? fm.removeItem(at: appSupportDir
                .appendingPathComponent(bundleID)
                .appendingPathComponent("webview-interaction"))
        }
    }

    /// Sets the ATB install date to 7 days ago so the promo cooldown is already satisfied.
    /// Also writes ATB keys so `hasInstallStatistics` returns true, preventing
    /// `StatisticsLoader.fireInstallPixel` from overwriting the backdated date.
    /// Persists the VARIANT environment variable into the statistics store so that
    /// `isReturningUser` checks inside promo coordinators match the onboarding path.
    private func backdateInstallDate(groupIdPrefix: String?) {
        guard let prefix = groupIdPrefix,
              let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return }

        let suite = "\(prefix).statistics"
        let statisticsDefaults = UserDefaults(suiteName: suite)
        statisticsDefaults?.set(sevenDaysAgo.timeIntervalSince1970, forKey: "com.duckduckgo.statistics.installdate.key")
        statisticsDefaults?.set("v1-1", forKey: "com.duckduckgo.statistics.atb.key")
        statisticsDefaults?.set("v1-1", forKey: "com.duckduckgo.statistics.retentionatb.key")
        statisticsDefaults?.set("v1-1", forKey: "com.duckduckgo.statistics.appretentionatb.key")
        if let variant = ProcessInfo.processInfo.environment["VARIANT"] {
            statisticsDefaults?.set(variant, forKey: "com.duckduckgo.statistics.variant.key")
        }
    }

    // MARK: - Feature flag / experiment override helpers

    private func applyFlagOverrides(featureFlagOverrideStore: KeyValueStoring, configRolloutStore: UserDefaults) {
        let persistor = FeatureFlagLocalOverridesUserDefaultsPersistor(keyValueStore: featureFlagOverrideStore)

        for arg in arguments {
            guard arg.hasPrefix("-") else { continue }
            let key = String(arg.dropFirst())

            if applyInternalUserOverrideIfPresent(key: key) { continue }
            applyFeatureFlagOverride(key: key, persistor: persistor)
            applyConfigRolloutOverride(key: key, configRolloutStore: configRolloutStore)
            applyExperimentOverride(key: key, persistor: persistor)
        }
    }

    private func applyInternalUserOverrideIfPresent(key: String) -> Bool {
        guard key == UITestOverrides.internalUserKey else { return false }
        if userDefaults.string(forKey: key)?.lowercased() == "true" {
            internalUserStore.isInternalUser = true
        }
        return true
    }

    // Feature flag: -ff.<flagName> true/false
    private func applyFeatureFlagOverride(key: String, persistor: FeatureFlagLocalOverridesUserDefaultsPersistor) {
        guard key.hasPrefix(UITestOverrides.featureFlagPrefix) else { return }
        let flagName = String(key.dropFirst(UITestOverrides.featureFlagPrefix.count))
        guard let flag = FeatureFlag(rawValue: flagName),
              let stringValue = userDefaults.string(forKey: key) else { return }
        persistor.set(stringValue.lowercased() == "true", for: flag)
    }

    // Config rollout: -config.rollout.<path> true/false → config.<path>.enabled
    private func applyConfigRolloutOverride(key: String, configRolloutStore: UserDefaults) {
        guard key.hasPrefix(UITestOverrides.configRolloutPrefix) else { return }
        let featurePath = String(key.dropFirst(UITestOverrides.configRolloutPrefix.count))
        guard let stringValue = userDefaults.string(forKey: key) else { return }
        configRolloutStore.set(stringValue.lowercased() == "true", forKey: "config.\(featurePath).enabled")
    }

    // Experiment: -experiment.<flagName> <cohortID>
    private func applyExperimentOverride(key: String, persistor: FeatureFlagLocalOverridesUserDefaultsPersistor) {
        guard key.hasPrefix(UITestOverrides.experimentCohortPrefix) else { return }
        let flagName = String(key.dropFirst(UITestOverrides.experimentCohortPrefix.count))
        guard let flag = FeatureFlag(rawValue: flagName),
              let cohortID = userDefaults.string(forKey: key), !cohortID.isEmpty else { return }
        persistor.setExperiment(cohortID, for: flag)
    }
}
