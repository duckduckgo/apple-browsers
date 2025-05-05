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

/// This struct serves as a wrapper for PrivacyConfigurationManaging, enabling the retrieval of data relevant to AIChat.
/// It also fire pixels when necessary data is missing.
struct AIChatSettings: AIChatSettingsProvider {
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
    private var remoteSettings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        privacyConfigurationManager.privacyConfig.settings(for: .aiChat)
    }
    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter

    init(privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         userDefaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = .default) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    // MARK: - Public

    var aiChatURL: URL {
        guard let url = URL(string: getSettingsData(.aiChatURL)) else {
            return URL(string: SettingsValue.aiChatURL.defaultValue)!
        }
        return url
    }

    var isAIChatEnabled: Bool {
        userDefaults.isAIChatEnabled
    }

    var isAIChatBrowsingMenuUserSettingsEnabled: Bool {
        userDefaults.showAIChatBrowsingMenu && isAIChatEnabled
    }

    var isAIChatAddressBarUserSettingsEnabled: Bool {
        userDefaults.showAIChatAddressBar && isAIChatEnabled
    }

    var isAIChatTabSwitcherUserSettingsEnabled: Bool {
        userDefaults.showAIChatTabSwitcher && isAIChatEnabled
    }

    var isAIChatVoiceSearchUserSettingsEnabled: Bool {
        userDefaults.showAIChatVoiceSearch && isAIChatEnabled
    }

    func enableAIChat(enable: Bool) {
        userDefaults.isAIChatEnabled = enable
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsEnabled)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsDisabled)
        }
    }

    func enableAIChatBrowsingMenuUserSettings(enable: Bool) {
        userDefaults.showAIChatBrowsingMenu = enable
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsBrowserMenuTurnedOn)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsBrowserMenuTurnedOff)
        }
    }

    func enableAIChatAddressBarUserSettings(enable: Bool) {
        userDefaults.showAIChatAddressBar = enable
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsAddressBarTurnedOn)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsAddressBarTurnedOff)
        }
    }

    func enableAIChatVoiceSearchUserSettings(enable: Bool) {
        userDefaults.showAIChatVoiceSearch = enable
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsVoiceTurnedOn)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsVoiceTurnedOff)
        }
    }

    func enableAIChatTabSwitcherUserSettings(enable: Bool) {
        userDefaults.showAIChatTabSwitcher = enable
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

private extension UserDefaults {
    enum Keys {
        static let isAIChatEnabled = "aichat.settings.isEnabled"
        static let showAIChatBrowsingMenu = "aichat.settings.showAIChatBrowsingMenu"
        static let showAIChatAddressBar = "aichat.settings.showAIChatAddressBar"
        static let showAIChatVoiceSearch = "aichat.settings.showAIChatVoiceSearch"
        static let showAIChatTabSwitcher = "aichat.settings.showAIChatTabSwitcher"

    }

    static let isAIChatEnabledDefaultValue = true
    static let showAIChatBrowsingMenuDefaultValue = true
    static let showAIChatAddressBarDefaultValue = true
    static let showAIChatVoiceSearchDefaultValue = true
    static let showAIChatTabSwitcherDefaultValue = true

    @objc dynamic var isAIChatEnabled: Bool {
        get {
            value(forKey: Keys.isAIChatEnabled) as? Bool ?? Self.isAIChatEnabledDefaultValue
        }

        set {
            guard newValue != isAIChatEnabled else { return }
            set(newValue, forKey: Keys.isAIChatEnabled)
        }
    }

    @objc dynamic var showAIChatBrowsingMenu: Bool {
        get {
            value(forKey: Keys.showAIChatBrowsingMenu) as? Bool ?? Self.showAIChatBrowsingMenuDefaultValue
        }

        set {
            guard newValue != showAIChatBrowsingMenu else { return }
            set(newValue, forKey: Keys.showAIChatBrowsingMenu)
        }
    }

    @objc dynamic var showAIChatVoiceSearch: Bool {
        get {
            value(forKey: Keys.showAIChatVoiceSearch) as? Bool ?? Self.showAIChatVoiceSearchDefaultValue
        }

        set {
            guard newValue != showAIChatVoiceSearch else { return }
            set(newValue, forKey: Keys.showAIChatVoiceSearch)
        }
    }

    @objc dynamic var showAIChatAddressBar: Bool {
        get {
            value(forKey: Keys.showAIChatAddressBar) as? Bool ?? Self.showAIChatAddressBarDefaultValue
        }

        set {
            guard newValue != showAIChatAddressBar else { return }
            set(newValue, forKey: Keys.showAIChatAddressBar)
        }
    }

    @objc dynamic var showAIChatTabSwitcher: Bool {
        get {
            value(forKey: Keys.showAIChatTabSwitcher) as? Bool ?? Self.showAIChatTabSwitcherDefaultValue
        }

        set {
            guard newValue != showAIChatTabSwitcher else { return }
            set(newValue, forKey: Keys.showAIChatTabSwitcher)
        }
    }
}

public extension NSNotification.Name {
    static let aiChatSettingsChanged = Notification.Name("com.duckduckgo.aichat.settings.changed")
}
