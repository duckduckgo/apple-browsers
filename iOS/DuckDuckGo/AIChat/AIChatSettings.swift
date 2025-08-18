//
//  AIChatSettings.swift
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

import BrowserServicesKit
import AIChat
import Foundation
import Core
import Persistence

/// This struct serves as a wrapper for PrivacyConfigurationManaging, enabling the retrieval of data relevant to AIChat.
/// It also fire pixels when necessary data is missing.
final class AIChatSettings: AIChatSettingsProvider {

    // Settings for KeepSession subfeature
    struct KeepSessionSettings: Codable {
        let sessionTimeoutMinutes: Int
        static let defaultSessionTimeoutInMinutes: Int = 60
    }

    enum SettingsValue: String {
        case aiChatURL

        var defaultValue: String {
            switch self {
                /// https://app.asana.com/0/1208541424548398/1208567543352020/f
            case .aiChatURL: return "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=4"
            }
        }
    }

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let debugSettings: AIChatDebugSettingsHandling
    private var remoteSettings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        privacyConfigurationManager.privacyConfig.settings(for: .aiChat)
    }
    private let keyValueStore: KeyValueStoring
    private let notificationCenter: NotificationCenter
    private let featureFlagger: FeatureFlagger
    init(privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         debugSettings: AIChatDebugSettingsHandling = AIChatDebugSettings(),
         keyValueStore: KeyValueStoring = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults(),
         notificationCenter: NotificationCenter = .default,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.debugSettings = debugSettings
        self.keyValueStore = keyValueStore
        self.notificationCenter = notificationCenter
        self.featureFlagger = featureFlagger
    }

    // MARK: - Public

    var aiChatURL: URL {
        // 1. First check for debug URL override
        if let debugURL = debugSettings.customURL,
           let url = URL(string: debugURL) {
            return url
        }
        
        // 2. Then check remote configuration
        guard let url = URL(string: getSettingsData(.aiChatURL)) else {
            return URL(string: SettingsValue.aiChatURL.defaultValue)!
        }
        return url
    }

    private var keepSessionSettings: KeepSessionSettings? {
        let decoder = JSONDecoder()

        if let settingsJSON = privacyConfigurationManager.privacyConfig.settings(for: AIChatSubfeature.keepSession),
           let jsonData = settingsJSON.data(using: .utf8) {
            do {
                let settings = try decoder.decode(KeepSessionSettings.self, from: jsonData)
                return settings
            } catch {
                return nil
            }
        }
        return nil
    }

    var sessionTimerInMinutes: Int {
        keepSessionSettings?.sessionTimeoutMinutes ?? KeepSessionSettings.defaultSessionTimeoutInMinutes
    }

    var isAIChatEnabled: Bool {
        keyValueStore.bool(.isAIChatEnabledKey, defaultValue: .isAIChatEnabledDefaultValue)
    }

    var isAIChatBrowsingMenuUserSettingsEnabled: Bool {
        keyValueStore.bool(.showAIChatBrowsingMenuKey, defaultValue: .showAIChatBrowsingMenuDefaultValue)
            && isAIChatEnabled
    }

    var isAIChatAddressBarUserSettingsEnabled: Bool {
        keyValueStore.bool(.showAIChatAddressBarKey, defaultValue: .showAIChatAddressBarDefaultValue)
            && isAIChatEnabled
    }

    var isAIChatTabSwitcherUserSettingsEnabled: Bool {
        keyValueStore.bool(.showAIChatTabSwitcherKey, defaultValue: .showAIChatTabSwitcherDefaultValue)
            && isAIChatEnabled
    }

    var isAIChatVoiceSearchUserSettingsEnabled: Bool {
        keyValueStore.bool(.showAIChatVoiceSearchKey, defaultValue: .showAIChatVoiceSearchDefaultValue)
            && isAIChatEnabled
    }

    var isAIChatSearchInputUserSettingsEnabled: Bool {
        keyValueStore.bool(.showAIChatExperimentalSearchInputKey, defaultValue: .showAIChatExperimentalSearchInputDefaultValue)
                            && isAIChatEnabled && featureFlagger.isFeatureOn(.experimentalAddressBar)
    }

    func enableAIChat(enable: Bool) {
        keyValueStore.set(enable, forKey: .isAIChatEnabledKey)
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsEnabled)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsDisabled)
        }
    }

    func enableAIChatBrowsingMenuUserSettings(enable: Bool) {
        keyValueStore.set(enable, forKey: .showAIChatBrowsingMenuKey)
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsBrowserMenuTurnedOn)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsBrowserMenuTurnedOff)
        }
    }

    func enableAIChatAddressBarUserSettings(enable: Bool) {
        keyValueStore.set(enable, forKey: .showAIChatAddressBarKey)
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsAddressBarTurnedOn)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsAddressBarTurnedOff)
        }
    }

    func enableAIChatSearchInputUserSettings(enable: Bool) {
        keyValueStore.set(enable, forKey: .showAIChatExperimentalSearchInputKey)
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsSearchInputTurnedOn)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsSearchInputTurnedOff)
        }
    }

    func enableAIChatVoiceSearchUserSettings(enable: Bool) {
        keyValueStore.set(enable, forKey: .showAIChatVoiceSearchKey)
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsVoiceTurnedOn)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsVoiceTurnedOff)
        }
    }

    func enableAIChatTabSwitcherUserSettings(enable: Bool) {
        keyValueStore.set(enable, forKey: .showAIChatTabSwitcherKey)
        triggerSettingsChangedNotification()
        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsTabManagerTurnedOn)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsTabManagerTurnedOff)
        }
    }

    // MARK: - Private

    private func triggerSettingsChangedNotification() {
        notificationCenter.post(name: .aiChatSettingsChanged, object: nil)
    }

    private func getSettingsData(_ value: SettingsValue) -> String {
        if let value = remoteSettings[value.rawValue] as? String {
            return value
        } else {
            Pixel.fire(pixel: .aiChatNoRemoteSettingsFound(settings: value.rawValue))
            return value.defaultValue
        }
    }
}

// MARK: - Keys for storage

private extension String {
    static let isAIChatEnabledKey = AppConfigurationKeyNames.isAIChatEnabled
    static let showAIChatBrowsingMenuKey = "aichat.settings.showAIChatBrowsingMenu"
    static let showAIChatAddressBarKey = "aichat.settings.showAIChatAddressBar"
    static let showAIChatVoiceSearchKey = "aichat.settings.showAIChatVoiceSearch"
    static let showAIChatTabSwitcherKey = "aichat.settings.showAIChatTabSwitcher"
    static let showAIChatExperimentalSearchInputKey = "aichat.settings.showAIChatExperimentalSearchInput"
}

enum LegacyAiChatUserDefaultsKeys {

    static let isAIChatEnabledKey: String = .isAIChatEnabledKey
    static let showAIChatBrowsingMenuKey: String = .showAIChatBrowsingMenuKey
    static let showAIChatAddressBarKey: String = .showAIChatAddressBarKey
    static let showAIChatVoiceSearchKey: String = .showAIChatVoiceSearchKey
    static let showAIChatTabSwitcherKey: String = .showAIChatTabSwitcherKey
    static let showAIChatExperimentalSearchInputKey: String = .showAIChatExperimentalSearchInputKey

}

// MARK: - Default values for storage

private extension Bool {

    static let isAIChatEnabledDefaultValue = true
    static let showAIChatBrowsingMenuDefaultValue = true
    static let showAIChatAddressBarDefaultValue = true
    static let showAIChatVoiceSearchDefaultValue = true
    static let showAIChatTabSwitcherDefaultValue = true
    static let showAIChatExperimentalSearchInputDefaultValue = false

}

public extension NSNotification.Name {
    static let aiChatSettingsChanged = Notification.Name("com.duckduckgo.aichat.settings.changed")
}

private extension KeyValueStoring {

    func bool(_ key: String, defaultValue: Bool) -> Bool {
        return (object(forKey: key) as? Bool) ?? defaultValue
    }

}
