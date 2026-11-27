//
//  IOSLaunchSettings.swift
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

#if DEBUG || ALPHA

import AIChat
import Common
import Configuration
import Core
import FeatureFlags_iOS
import Foundation
import LaunchProfile
import Persistence
import PrivacyConfig

/// Every key a `-launchProfile` can set on iOS. Settings apply in the order listed in `make`.
/// To add a key, add a factory that takes only the store it writes and list it in `make`, or in the group it belongs to:
/// `IOSLaunchSettings+Settings.swift` for the Settings screen, `+DuckAI.swift` for Duck.ai, `+Debug.swift` for the Debug menu.
@MainActor
enum IOSLaunchSettings {

    /// Sets a value for this launch only, exactly as passing `-<key> <value>` would.
    typealias SetLaunchArgument = (_ value: String, _ key: String) -> Void

    /// The stores launch keys write to. Live values come from `LaunchProfileStartup`; tests pass their own.
    struct Dependencies {
        var internalUserStore: InternalUserStoring
        var flagOverridesNeedInternalUser: Bool
        var setLaunchArgument: SetLaunchArgument
        var tabsPersistence: () throws -> TabsModelPersisting
        var isPad: Bool
        var appSettings: AppSettings
        var appDefaults: UserDefaults
        /// The app-configuration group: Duck.ai settings and custom configuration URLs.
        var appConfigurationDefaults: UserDefaults
        var aiChatDebugSettings: AIChatDebugSettingsHandling
        /// The app's key-value file store, opened only when a key writes to it.
        var appKeyValueStore: () throws -> ThrowingKeyValueStoring
    }

    static func make(_ dependencies: Dependencies) -> LaunchSettings {
        let flagRequirements = dependencies.flagOverridesNeedInternalUser ? requiresInternalUser : [:]
        return LaunchSettings(
            [internalUser(store: dependencies.internalUserStore),
             onboardingCompleted(setLaunchArgument: dependencies.setLaunchArgument)]
            + featureFlags(setLaunchArgument: dependencies.setLaunchArgument, requires: flagRequirements)
            + experiments(setLaunchArgument: dependencies.setLaunchArgument, requires: flagRequirements)
            + [privacyConfigURL(setLaunchArgument: dependencies.setLaunchArgument)]
            + settingsScreen(dependencies.appSettings)
            + duckAI(AIChatUserSettingsStore(keyValueStore: dependencies.appConfigurationDefaults, pixelFiring: { nil }))
            + debugMenu(appSettings: dependencies.appSettings,
                        appDefaults: dependencies.appDefaults,
                        aiChatDebugSettings: dependencies.aiChatDebugSettings,
                        customConfigurationURLs: CustomConfigurationURLStorage(defaults: dependencies.appConfigurationDefaults),
                        appKeyValueStore: dependencies.appKeyValueStore)
            + [tabs(persistence: dependencies.tabsPersistence, isPad: dependencies.isPad)]
        )
    }

    static let requiresInternalUser: [String: LaunchProfileValue] = ["internalUser": .bool(true)]

    static func internalUser(store: InternalUserStoring) -> LaunchSetting {
        LaunchSetting("internalUser", summary: "Makes the app treat this user as internal, which feature flag overrides need.") { (isInternal: Bool) in
            var store = store
            store.isInternalUser = isInternal
        }
    }

    static func onboardingCompleted(setLaunchArgument: @escaping SetLaunchArgument) -> LaunchSetting {
        LaunchSetting("onboardingCompleted", summary: "true skips onboarding; false shows it. Same as -isOnboardingCompleted.") { (isCompleted: Bool) in
            setLaunchArgument(String(isCompleted), LaunchOptionsHandler.isOnboardingCompleted)
        }
    }

    /// Saved, not one launch: `LaunchOptionsHandler.applyFlagOverrides` copies these arguments into the override store.
    static func featureFlags(setLaunchArgument: @escaping SetLaunchArgument, requires requirements: [String: LaunchProfileValue]) -> [LaunchSetting] {
        FeatureFlag.allCases.filter(\.supportsLocalOverriding).map { flag in
            LaunchSetting("featureFlags.\(flag.rawValue)",
                          summary: "Overrides the \(flag.rawValue) feature flag. Same as -ff.\(flag.rawValue).",
                          requires: requirements) { (isOn: Bool) in
                setLaunchArgument(String(isOn), LaunchOptionsHandler.featureFlagArgumentKey(for: flag))
            }
        }
    }

    static func experiments(setLaunchArgument: @escaping SetLaunchArgument, requires requirements: [String: LaunchProfileValue]) -> [LaunchSetting] {
        FeatureFlag.allCases.filter(\.supportsLocalOverriding).compactMap { flag in
            guard let cohortType = flag.cohortType else { return nil }
            let cohortIDs = cohortIDs(of: cohortType)
            return LaunchSetting("experiments.\(flag.rawValue)",
                                 summary: "Puts this user in a cohort of the \(flag.rawValue) experiment: \(cohortIDs.joined(separator: ", ")).",
                                 requires: requirements,
                                 validate: { (cohortID: String) in
                guard cohortIDs.contains(cohortID) else {
                    throw LaunchSettingInvalidValue("use one of \(cohortIDs.joined(separator: ", ")).")
                }
            }, write: { cohortID in
                setLaunchArgument(cohortID, LaunchOptionsHandler.experimentArgumentKey(for: flag))
            })
        }
    }

    static func privacyConfigURL(setLaunchArgument: @escaping SetLaunchArgument) -> LaunchSetting {
        let key = PrivacyConfigurationOverrideArgument.launchArgumentKey
        return LaunchSetting(key,
                             summary: "Loads the privacy configuration from this URL for this launch only. Same as -\(key).",
                             requires: requiresInternalUser,
                             validate: { (url: String) in
            guard PrivacyConfigurationOverrideArgument.url(fromLaunchArgument: url) != nil else {
                throw LaunchSettingInvalidValue("use an http or https URL.")
            }
        }, write: { url in
            setLaunchArgument(url, key)
        })
    }

    static func tabs(persistence: @escaping () throws -> TabsModelPersisting, isPad: Bool) -> LaunchSetting {
        LaunchSetting("tabs",
                      summary: "Replaces the open tabs with these URLs and closes Fire tabs; the last one is selected.",
                      validate: { (urls: [URL]) in
            try urls.forEach(requireWebPage)
        }, write: { urls in
            let tabs = urls.map { Tab(link: Link(title: nil, url: $0), desktop: isPad, fireTab: false) }
            let model = TabsModel(tabs: tabs, currentIndex: max(tabs.count - 1, 0), desktop: isPad)
            let persistence = try persistence()
            try persistence.saveSynchronously(model: model, for: .normal).get()
            persistence.clear(for: .fire)
        })
    }

    static func requireWebPage(_ url: URL) throws {
        guard (url.isHttp || url.isHttps) && url.host?.isEmpty == false else {
            throw LaunchSettingInvalidValue("use http or https URLs, like https://example.com.")
        }
    }

    private static func cohortIDs<Cohort: FeatureFlagCohortDescribing>(of type: Cohort.Type) -> [String] {
        Cohort.allCases.map(\.rawValue)
    }
}

#endif
