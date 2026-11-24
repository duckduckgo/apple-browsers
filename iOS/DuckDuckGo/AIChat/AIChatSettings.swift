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
import Combine
import Foundation
import Core
import Persistence
import FeatureFlags_iOS
import PixelKit

/// This struct serves as a wrapper for PrivacyConfigurationManaging, enabling the retrieval of data relevant to AIChat.
/// It also fire pixels when necessary data is missing.
final class AIChatSettings: AIChatSettingsProvider {

    // Settings for KeepSession subfeature
    struct KeepSessionSettings: Codable {
        let sessionTimeoutMinutes: Int
        static let defaultSessionTimeoutInMinutes: Int = 60
    }

    struct AttachMoreTabsSettings: Decodable {
        let aiChatAttachMoreTabsLimit: Int
        static let defaultLimit: Int = 3
    }

    struct AttachMoreTabsPromotionSettings: Decodable {
        let promotionStartDate: Date
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
    private let pixelFiring: (any PixelKitFiring)?
    private let userSettings: AIChatUserSettingsStore

    init(privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         debugSettings: AIChatDebugSettingsHandling = AIChatDebugSettings(),
         keyValueStore: KeyValueStoring = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults(),
         notificationCenter: NotificationCenter = .default,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.debugSettings = debugSettings
        self.keyValueStore = keyValueStore
        self.notificationCenter = notificationCenter
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.userSettings = AIChatUserSettingsStore(keyValueStore: keyValueStore, notificationCenter: notificationCenter)

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

    var aiChatAttachMoreTabsLimit: Int {
        guard let settingsJSON = privacyConfigurationManager.privacyConfig.settings(for: AIChatSubfeature.contextualAttachMoreTabs),
              let jsonData = settingsJSON.data(using: .utf8),
              let limit = try? JSONDecoder().decode(AttachMoreTabsSettings.self, from: jsonData).aiChatAttachMoreTabsLimit,
              limit > 0 else {
            return AttachMoreTabsSettings.defaultLimit
        }

        return limit
    }

    var aiChatAttachMoreTabsPromotionStartDate: Date? {
        guard let settingsJSON = privacyConfigurationManager.privacyConfig.settings(for: AIChatSubfeature.contextualAttachMoreTabs),
              let jsonData = settingsJSON.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AttachMoreTabsPromotionSettings.self, from: jsonData).promotionStartDate
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
            && isAIChatEnabled
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

    var isKeyboardAnimationEnabled: Bool {
        keyValueStore.bool(.isKeyboardAnimationEnabledKey, defaultValue: true)
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
        userSettings.set(.duckAI, isOn: enable)
    }

    func enableAIChatBrowsingMenuUserSettings(enable: Bool) {
        userSettings.set(.browsingMenu, isOn: enable)
    }

    func enableAIChatAddressBarUserSettings(enable: Bool) {
        userSettings.set(.addressBar, isOn: enable)
    }

    func enableAIChatSearchInputUserSettings(enable: Bool) {
        userSettings.set(.searchInput, isOn: enable)
    }

    /// Removes the user's selection for the AI Chat experimental search input toggle,
    /// returning it to its un-set state (subsequent reads fall back to the default).
    func resetAIChatSearchInputUserSettings() {
        keyValueStore.removeObject(forKey: .showAIChatExperimentalSearchInputKey)
        triggerSettingsChangedNotification()
    }

    func enableAIChatVoiceSearchUserSettings(enable: Bool) {
        userSettings.set(.voiceSearch, isOn: enable)
    }

    func enableAIChatTabSwitcherUserSettings(enable: Bool) {
        userSettings.set(.tabSwitcher, isOn: enable)
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
        userSettings.set(.chatSuggestions, isOn: enable)
    }
    
    func enableAutomaticContextAttachment(enable: Bool) {
        userSettings.set(.automaticContextAttachment, isOn: enable)
    }

    func enableKeyboardAnimation(enable: Bool) {
        let wasEnabled = isKeyboardAnimationEnabled
        keyValueStore.set(enable, forKey: .isKeyboardAnimationEnabledKey)
        triggerSettingsChangedNotification()

        if wasEnabled && !enable {
            pixelFiring?.fire(DuckAIKeyboardAnimationPixel.disabled, frequency: .dailyAndCount)
        }
    }

    func setDefaultOmnibarMode(_ mode: DefaultOmnibarMode) {
        guard featureFlagger.isFeatureOn(.aiChatOmnibarDefaultPosition) else {
            return
        }

        userSettings.setDefaultOmnibarMode(mode)
    }

    // MARK: - Private

    private func triggerSettingsChangedNotification() {
        notificationCenter.post(name: .aiChatSettingsChanged, object: nil)
    }

    private func getSettingsData(_ value: SettingsValue) -> String {
        if let value = remoteSettings[value.rawValue] as? String {
            return value
        } else {
            PixelKit.fire(Pixel.Event.aiChatNoRemoteSettingsFound(settings: value.rawValue))
            return value.defaultValue
        }
    }
    
}

extension AIChatSettings: AIChatPageSummariesModelStoring {

    var pageSummariesModel: AIChatPageSummariesModel {
        get {
            (keyValueStore.object(forKey: .pageSummariesModelKey) as? String).flatMap(AIChatPageSummariesModel.init(rawValue:)) ?? .duckAI
        }
        set {
            userSettings.setPageSummariesModel(newValue)
        }
    }

    /// Other `AIChatSettings` instances write to the same store, so this follows the shared notification.
    var pageSummariesModelPublisher: AnyPublisher<AIChatPageSummariesModel, Never> {
        notificationCenter.publisher(for: .aiChatSettingsChanged)
            .compactMap { [weak self] _ in self?.pageSummariesModel }
            .prepend(pageSummariesModel)
            .eraseToAnyPublisher()
    }
}

/// The Duck.ai options a user turns on or off in Settings: saves the choice, posts `.aiChatSettingsChanged` and sends its pixel.
/// Needs no app service, so a launch profile can write through it before the app's services start.
struct AIChatUserSettingsStore {

    enum Toggle: CaseIterable {
        case duckAI, browsingMenu, addressBar, searchInput, voiceSearch, tabSwitcher, chatSuggestions, automaticContextAttachment
    }

    private let keyValueStore: KeyValueStoring
    private let notificationCenter: NotificationCenter
    /// Resolved at fire time, so a store made before `PixelKit.setUp` still sends pixels. Return nil to send none.
    private let pixelFiring: () -> (any PixelKitFiring)?

    init(keyValueStore: KeyValueStoring,
         notificationCenter: NotificationCenter = .default,
         pixelFiring: @escaping () -> (any PixelKitFiring)? = { PixelKit.shared }) {
        self.keyValueStore = keyValueStore
        self.notificationCenter = notificationCenter
        self.pixelFiring = pixelFiring
    }

    func set(_ toggle: Toggle, isOn: Bool) {
        keyValueStore.set(isOn, forKey: toggle.storageKey)
        notificationCenter.post(name: .aiChatSettingsChanged, object: nil)
        pixelFiring()?.fire(isOn ? toggle.turnedOnPixel : toggle.turnedOffPixel, frequency: .dailyAndCount)
    }

    func setDefaultOmnibarMode(_ mode: DefaultOmnibarMode) {
        keyValueStore.set(mode.rawValue, forKey: .defaultOmnibarModeKey)
        notificationCenter.post(name: .aiChatSettingsChanged, object: nil)
        pixelFiring()?.fire(Pixel.Event.aiChatSettingsDefaultTogglePositionChanged,
                            frequency: .dailyAndCount,
                            options: .parameters(["value": mode.rawValue]))
    }

    func setPageSummariesModel(_ model: AIChatPageSummariesModel) {
        keyValueStore.set(model.rawValue, forKey: .pageSummariesModelKey)
        notificationCenter.post(name: .aiChatSettingsChanged, object: nil)
    }
}

private extension AIChatUserSettingsStore.Toggle {

    var storageKey: String {
        switch self {
        case .duckAI: return .isAIChatEnabledKey
        case .browsingMenu: return .showAIChatBrowsingMenuKey
        case .addressBar: return .showAIChatAddressBarKey
        case .searchInput: return .showAIChatExperimentalSearchInputKey
        case .voiceSearch: return .showAIChatVoiceSearchKey
        case .tabSwitcher: return .showAIChatTabSwitcherKey
        case .chatSuggestions: return .showChatSuggestionsKey
        case .automaticContextAttachment: return .isAIChatAutomaticContextAttachmentEnabledKey
        }
    }

    var turnedOnPixel: Pixel.Event {
        switch self {
        case .duckAI: return .aiChatSettingsEnabled
        case .browsingMenu: return .aiChatSettingsBrowserMenuTurnedOn
        case .addressBar: return .aiChatSettingsAddressBarTurnedOn
        case .searchInput: return .aiChatSettingsSearchInputTurnedOn
        case .voiceSearch: return .aiChatSettingsVoiceTurnedOn
        case .tabSwitcher: return .aiChatSettingsTabManagerTurnedOn
        case .chatSuggestions: return .aiChatSettingsChatSuggestionsTurnedOn
        case .automaticContextAttachment: return .aiChatSettingsAutoContextEnabled
        }
    }

    var turnedOffPixel: Pixel.Event {
        switch self {
        case .duckAI: return .aiChatSettingsDisabled
        case .browsingMenu: return .aiChatSettingsBrowserMenuTurnedOff
        case .addressBar: return .aiChatSettingsAddressBarTurnedOff
        case .searchInput: return .aiChatSettingsSearchInputTurnedOff
        case .voiceSearch: return .aiChatSettingsVoiceTurnedOff
        case .tabSwitcher: return .aiChatSettingsTabManagerTurnedOff
        case .chatSuggestions: return .aiChatSettingsChatSuggestionsTurnedOff
        case .automaticContextAttachment: return .aiChatSettingsAutoContextDisabled
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
    static let showAIChatTabBarKey = "aichat.settings.showAIChatTabBar"
    static let showAIChatTabBarDuckAIButtonKey = "aichat.settings.showAIChatTabBarDuckAIButton"
    static let showAIChatTabBarContextualSheetKey = "aichat.settings.showAIChatTabBarContextualSheet"
    static let showAIChatExperimentalSearchInputKey = "aichat.settings.showAIChatExperimentalSearchInput"
    static let showChatSuggestionsKey = "aichat.settings.showChatSuggestions"
    static let isAIChatAutomaticContextAttachmentEnabledKey = "aichat.settings.isAIChatAutomaticContextAttachmentEnabled"
    static let isKeyboardAnimationEnabledKey = "aichat.settings.isKeyboardAnimationEnabled"
    static let defaultOmnibarModeKey = "aichat.settings.defaultOmnibarMode"
    static let pageSummariesModelKey = "aichat.settings.pageSummariesModel"
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
