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

import PrivacyConfig
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
    private let switchBarFunnel: SwitchBarFunnelProviding
    
    init(privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         debugSettings: AIChatDebugSettingsHandling = AIChatDebugSettings(),
         keyValueStore: KeyValueStoring = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults(),
         notificationCenter: NotificationCenter = .default,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         switchBarFunnel: SwitchBarFunnelProviding = SwitchBarFunnel(storage: UserDefaults.standard)) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.debugSettings = debugSettings
        self.keyValueStore = keyValueStore
        self.notificationCenter = notificationCenter
        self.featureFlagger = featureFlagger
        self.switchBarFunnel = switchBarFunnel

        migrateAddressBarSettingIfNeeded()
    }

    /// One-shot: if a user had the legacy Address Bar toggle off, carry that into the
    /// Tab Bar toggle so the iPad chrome shortcut doesn't silently re-enable the
    /// surface under a new name.
    private func migrateAddressBarSettingIfNeeded() {
        guard keyValueStore.object(forKey: .showAIChatTabBarKey) == nil,
              let legacyAddressBarValue = keyValueStore.object(forKey: .showAIChatAddressBarKey) as? Bool,
              legacyAddressBarValue == false else {
            return
        }
        keyValueStore.set(false, forKey: .showAIChatTabBarKey)
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

    /// Master on/off for the iPad tabs-bar Duck.ai shortcut (the single "Tab Bar" Settings toggle).
    var isAIChatTabBarUserSettingsEnabled: Bool {
        keyValueStore.bool(.showAIChatTabBarKey, defaultValue: .showAIChatTabBarDefaultValue)
            && isAIChatEnabled
    }

    /// Per-half visibility, toggled from the chip's long-press menu (not Settings).
    var isAIChatTabBarDuckAIButtonVisible: Bool {
        keyValueStore.bool(.showAIChatTabBarDuckAIButtonKey, defaultValue: .showAIChatTabBarDuckAIButtonDefaultValue)
    }

    var isAIChatTabBarContextualSheetButtonVisible: Bool {
        keyValueStore.bool(.showAIChatTabBarContextualSheetKey, defaultValue: .showAIChatTabBarContextualSheetDefaultValue)
    }

    var isAIChatVoiceSearchUserSettingsEnabled: Bool {
        keyValueStore.bool(.showAIChatVoiceSearchKey, defaultValue: .showAIChatVoiceSearchDefaultValue)
            && isAIChatEnabled
    }

    var isAIChatSearchInputUserSettingsEnabled: Bool {
        keyValueStore.bool(.showAIChatExperimentalSearchInputKey, defaultValue: .showAIChatExperimentalSearchInputDefaultValue)
                            && isAIChatEnabled && featureFlagger.isFeatureOn(.experimentalAddressBar)
    }

    var isAIChatSearchInputUserSettingsDisabledByUser: Bool {
        keyValueStore.bool(.showAIChatExperimentalSearchInputKey) == false
    }

    var isChatSuggestionsEnabled: Bool {
        keyValueStore.bool(.showChatSuggestionsKey, defaultValue: .showChatSuggestionsDefaultValue)
            && isAIChatEnabled
    }

    var isAutomaticContextAttachmentEnabled: Bool {
        keyValueStore.bool(.isAIChatAutomaticContextAttachmentEnabledKey, defaultValue: featureFlagger.isFeatureOn(.aiChatAutoAttachContextByDefault))
    }

    var defaultOmnibarMode: DefaultOmnibarMode {
        guard featureFlagger.isFeatureOn(.aiChatOmnibarDefaultPosition) else {
            return .search
        }

        guard let rawValue = keyValueStore.object(forKey: .defaultOmnibarModeKey) as? String,
              let mode = DefaultOmnibarMode(rawValue: rawValue) else {
            return .search
        }
        return mode
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
            
            
            // Process feature enabled funnel step
            switchBarFunnel.processStep(.featureEnabled)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsSearchInputTurnedOff)
            
            // Reset funnel when feature is disabled
            resetFunnelStorage()
        }
    }

    /// Removes the user's selection for the AI Chat experimental search input toggle,
    /// returning it to its un-set state (subsequent reads fall back to the default).
    func resetAIChatSearchInputUserSettings() {
        keyValueStore.removeObject(forKey: .showAIChatExperimentalSearchInputKey)
        triggerSettingsChangedNotification()
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

    func enableAIChatTabBarUserSettings(enable: Bool) {
        keyValueStore.set(enable, forKey: .showAIChatTabBarKey)
        // Re-enabling restores both halves — the only way back if the user hid both from the menu.
        if enable {
            keyValueStore.set(true, forKey: .showAIChatTabBarDuckAIButtonKey)
            keyValueStore.set(true, forKey: .showAIChatTabBarContextualSheetKey)
        }
        triggerSettingsChangedNotification()
    }

    func setAIChatTabBarDuckAIButtonVisible(_ visible: Bool) {
        keyValueStore.set(visible, forKey: .showAIChatTabBarDuckAIButtonKey)
        disableTabBarShortcutIfBothHalvesHidden()
        triggerSettingsChangedNotification()
    }

    func setAIChatTabBarContextualSheetButtonVisible(_ visible: Bool) {
        keyValueStore.set(visible, forKey: .showAIChatTabBarContextualSheetKey)
        disableTabBarShortcutIfBothHalvesHidden()
        triggerSettingsChangedNotification()
    }

    /// When the user hides both halves from the chip's menu, the shortcut shows nothing — turn the
    /// master Tab Bar toggle off so it reflects reality. Re-enabling it restores both halves.
    private func disableTabBarShortcutIfBothHalvesHidden() {
        let duckAIVisible = keyValueStore.bool(.showAIChatTabBarDuckAIButtonKey, defaultValue: .showAIChatTabBarDuckAIButtonDefaultValue)
        let bottomSheetVisible = keyValueStore.bool(.showAIChatTabBarContextualSheetKey, defaultValue: .showAIChatTabBarContextualSheetDefaultValue)
        if !duckAIVisible && !bottomSheetVisible {
            keyValueStore.set(false, forKey: .showAIChatTabBarKey)
        }
    }

    func enableChatSuggestions(enable: Bool) {
        keyValueStore.set(enable, forKey: .showChatSuggestionsKey)
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsChatSuggestionsTurnedOn)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsChatSuggestionsTurnedOff)
        }
    }
    
    func enableAutomaticContextAttachment(enable: Bool) {
        keyValueStore.set(enable, forKey: .isAIChatAutomaticContextAttachmentEnabledKey)
        triggerSettingsChangedNotification()

        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsAutoContextEnabled)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsAutoContextDisabled)
        }
    }

    func setDefaultOmnibarMode(_ mode: DefaultOmnibarMode) {
        guard featureFlagger.isFeatureOn(.aiChatOmnibarDefaultPosition) else {
            return
        }

        keyValueStore.set(mode.rawValue, forKey: .defaultOmnibarModeKey)
        triggerSettingsChangedNotification()
        DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsDefaultTogglePositionChanged,
                                      withAdditionalParameters: ["value": mode.rawValue])
    }

    /// Process the settings view funnels step
    func processSettingsViewedFunnelStep() {
        if !isAIChatSearchInputUserSettingsEnabled {
            switchBarFunnel.processStep(.settingsViewed)
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
    
    /// Reset all funnel storage when the new input feature is disabled
    private func resetFunnelStorage() {
        switchBarFunnel.resetAllFunnelState()
    }
}

// MARK: - Keys for storage

private extension String {
    static let isAIChatEnabledKey = AppConfigurationKeyNames.isAIChatEnabled
    static let showAIChatBrowsingMenuKey = "aichat.settings.showAIChatBrowsingMenu"
    static let showAIChatAddressBarKey = "aichat.settings.showAIChatAddressBar"
    static let showAIChatVoiceSearchKey = "aichat.settings.showAIChatVoiceSearch"
    static let showAIChatTabSwitcherKey = "aichat.settings.showAIChatTabSwitcher"
    static let showAIChatTabBarKey = "aichat.settings.showAIChatTabBar"
    static let showAIChatTabBarDuckAIButtonKey = "aichat.settings.showAIChatTabBarDuckAIButton"
    static let showAIChatTabBarContextualSheetKey = "aichat.settings.showAIChatTabBarContextualSheet"
    static let showAIChatExperimentalSearchInputKey = "aichat.settings.showAIChatExperimentalSearchInput"
    static let showChatSuggestionsKey = "aichat.settings.showChatSuggestions"
    static let isAIChatAutomaticContextAttachmentEnabledKey = "aichat.settings.isAIChatAutomaticContextAttachmentEnabled"
    static let defaultOmnibarModeKey = "aichat.settings.defaultOmnibarMode"
}

enum LegacyAiChatUserDefaultsKeys {

    static let isAIChatEnabledKey: String = .isAIChatEnabledKey
    static let showAIChatBrowsingMenuKey: String = .showAIChatBrowsingMenuKey
    static let showAIChatAddressBarKey: String = .showAIChatAddressBarKey
    static let showAIChatVoiceSearchKey: String = .showAIChatVoiceSearchKey
    static let showAIChatTabSwitcherKey: String = .showAIChatTabSwitcherKey
    static let showAIChatTabBarKey: String = .showAIChatTabBarKey
    static let showAIChatTabBarDuckAIButtonKey: String = .showAIChatTabBarDuckAIButtonKey
    static let showAIChatTabBarContextualSheetKey: String = .showAIChatTabBarContextualSheetKey
    static let showAIChatExperimentalSearchInputKey: String = .showAIChatExperimentalSearchInputKey
    static let defaultOmnibarModeKey: String = .defaultOmnibarModeKey

}

// MARK: - Default values for storage

private extension Bool {

    static let isAIChatEnabledDefaultValue = true
    static let showAIChatBrowsingMenuDefaultValue = true
    static let showAIChatAddressBarDefaultValue = true
    static let showAIChatVoiceSearchDefaultValue = true
    static let showAIChatTabSwitcherDefaultValue = true
    static let showAIChatTabBarDefaultValue = true
    static let showAIChatTabBarDuckAIButtonDefaultValue = true
    static let showAIChatTabBarContextualSheetDefaultValue = true
    static let showAIChatExperimentalSearchInputDefaultValue = false
    static let showChatSuggestionsDefaultValue = true

}

public extension NSNotification.Name {
    static let aiChatSettingsChanged = Notification.Name("com.duckduckgo.aichat.settings.changed")
}

private extension KeyValueStoring {

    func bool(_ key: String, defaultValue: Bool) -> Bool {
        return (object(forKey: key) as? Bool) ?? defaultValue
    }

    func bool(_ key: String) -> Bool? {
        return object(forKey: key) as? Bool
    }
}

extension DefaultOmnibarMode {

    func resolvedTextEntryMode(lastUsedModeProvider: () -> TextEntryMode?) -> TextEntryMode {
        switch self {
        case .search:
            return .search
        case .duckAI:
            return .aiChat
        case .lastUsed:
            return lastUsedModeProvider() ?? .search
        }
    }
}
