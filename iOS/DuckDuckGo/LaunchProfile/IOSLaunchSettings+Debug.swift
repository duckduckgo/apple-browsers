//
//  IOSLaunchSettings+Debug.swift
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
import Configuration
import Core
import DDGSync
import Foundation
import LaunchProfile
import Onboarding
import Persistence

/// Debug menu options, written through the same stores the Debug menu writes. They persist like a Debug menu change.
extension IOSLaunchSettings {

    static func debugMenu(appSettings: AppSettings,
                          appDefaults: UserDefaults,
                          aiChatDebugSettings: AIChatDebugSettingsHandling,
                          customConfigurationURLs urlStore: CustomConfigurationURLStoring,
                          appKeyValueStore: @escaping () throws -> ThrowingKeyValueStoring) -> [LaunchSetting] {
        [onboardingUserType(appSettings),
         onboardingFlowType(appSettings),
         duckAICustomURL(aiChatDebugSettings),
         idleReturnThreshold(appDefaults.keyedStoring()),
         syncEnvironment(appDefaults)]
        + customConfigurationURLs(urlStore)
        + subscriptionTokenRefresh(appKeyValueStore)
    }

    static func onboardingUserType(_ settings: AppSettings) -> LaunchSetting {
        .choice("debug.onboarding.userType",
                summary: "Treats this install as new or returning during onboarding.",
                options: OnboardingUserType.allCases,
                name: \.rawValue) { userType in
            var settings = settings
            settings.onboardingUserType = userType
        }
    }

    static func onboardingFlowType(_ settings: AppSettings) -> LaunchSetting {
        let flows: [OnboardingFlowType] = [.default, .duckAI]
        return .choice("debug.onboarding.flowType",
                       summary: "Forces this onboarding flow.",
                       options: flows,
                       name: \.rawValue) { flow in
            var settings = settings
            settings.onboardingFlowType = flow
        }
    }

    static func duckAICustomURL(_ debugSettings: AIChatDebugSettingsHandling) -> LaunchSetting {
        LaunchSetting("debug.duckAI.customURL",
                      summary: "Loads Duck.ai from this URL instead of duck.ai.",
                      validate: requireWebPage,
                      write: { (url: URL) in
            var debugSettings = debugSettings
            debugSettings.customURL = url.absoluteString
        })
    }

    static func idleReturnThreshold(_ storage: any KeyedStoring<IdleReturnDebugOverridesKeys>) -> LaunchSetting {
        LaunchSetting("debug.idleReturnThresholdSeconds",
                      summary: "Seconds in the background after which the app returns to a new tab page.",
                      validate: { (seconds: Int) in
            guard seconds > 0 else { throw LaunchSettingInvalidValue("use a number of seconds above 0.") }
        }, write: { storage.thresholdSecondsOverride = $0 })
    }

    static func syncEnvironment(_ appDefaults: UserDefaults) -> LaunchSetting {
        let environments: [ServerEnvironment] = [.production, .development]
        return .choice("debug.syncEnvironment",
                       summary: "Sync server the app talks to. Use it signed out of Sync: an existing account stays on its server.",
                       options: environments,
                       name: \.description) { environment in
            appDefaults.set(environment.description, forKey: UserDefaultsWrapper<String>.Key.syncEnvironment.rawValue)
        }
    }

    /// Only internal users get the token refresh overrides; see `SubscriptionTokenRefreshIntervals`.
    static func subscriptionTokenRefresh(_ store: @escaping () throws -> ThrowingKeyValueStoring) -> [LaunchSetting] {
        [LaunchSetting("debug.subscription.tokenRefreshAgeSeconds",
                       summary: "Refreshes the subscription token once its refresh token is this many seconds old, instead of 15 days.",
                       requires: requiresInternalUser,
                       validate: requirePositiveSeconds,
                       write: { (seconds: Int) in
            SubscriptionTokenRefreshDebugSettings(keyValueStore: try store()).maxRefreshTokenAgeOverride = TimeInterval(seconds)
        }),
         LaunchSetting("debug.subscription.tokenRefreshRetrySeconds",
                       summary: "Retries a failed subscription token refresh after this many seconds, instead of 6 hours.",
                       requires: requiresInternalUser,
                       validate: requirePositiveSeconds,
                       write: { (seconds: Int) in
            SubscriptionTokenRefreshDebugSettings(keyValueStore: try store()).retryIntervalOverride = TimeInterval(seconds)
        })]
    }

    private static func requirePositiveSeconds(_ seconds: Int) throws {
        guard seconds > 0 else { throw LaunchSettingInvalidValue("use a number of seconds above 0.") }
    }

    /// Only internal users load configuration from custom URLs.
    static func customConfigurationURLs(_ store: CustomConfigurationURLStoring) -> [LaunchSetting] {
        Configuration.allCases.map { configuration in
            LaunchSetting("debug.configURLs.\(configuration.rawValue)",
                          summary: "Loads \(configuration.rawValue) from this URL on every launch until the Debug menu clears it or the app is reinstalled.",
                          requires: requiresInternalUser,
                          validate: requireWebPage,
                          write: { (url: URL) in
                var store = store
                store[keyPath: customURLKeyPath(for: configuration)] = url
            })
        }
    }

    private static func customURLKeyPath(for configuration: Configuration) -> WritableKeyPath<CustomConfigurationURLStoring, URL?> {
        switch configuration {
        case .bloomFilterBinary: \.customBloomFilterBinaryURL
        case .bloomFilterSpec: \.customBloomFilterSpecURL
        case .bloomFilterExcludedDomains: \.customBloomFilterExcludedDomainsURL
        case .privacyConfiguration: \.customPrivacyConfigurationURL
        case .surrogates: \.customSurrogatesURL
        case .trackerDataSet: \.customTrackerDataSetURL
        case .remoteMessagingConfig: \.customRemoteMessagingConfigURL
        }
    }
}

#endif
