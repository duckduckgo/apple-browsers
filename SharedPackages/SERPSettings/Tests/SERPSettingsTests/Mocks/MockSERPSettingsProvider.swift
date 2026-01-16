//
//  MockSERPSettingsProvider.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import UserScript
import AIChat
import Common
import Persistence
import PersistenceTestingUtils
@testable import SERPSettings

final class MockSERPSettingsProvider: SERPSettingsProviding {

    // Configurable mock properties
    var mockIsSERPSettingsFeatureOn: Bool = true
    var mockIsAIChatEnabled: Bool = false

    // Required protocol properties
    var keyValueStore: ThrowingKeyValueStoring?
    var eventMapper: EventMapping<SERPSettingsError>?
    var wasStoreSettingsCalled: Bool = false

#if os(iOS)
    var aiChatProvider: AIChatSettingsProvider
#endif
#if os(macOS)
    var aiChatPreferencesStorage: AIChatPreferencesStorage
#endif

    init(keyValueStore: ThrowingKeyValueStoring,
         mockIsSERPSettingsFeatureOn: Bool = true) {
        self.keyValueStore = keyValueStore
        self.mockIsSERPSettingsFeatureOn = mockIsSERPSettingsFeatureOn

#if os(iOS)
        self.aiChatProvider = MockAIChatSettingsProvider()
#endif
#if os(macOS)
        self.aiChatPreferencesStorage = MockAIChatPreferencesStorage()
#endif
    }

    func buildMessageOriginRules() -> [HostnameMatchingRule] {
        return [.exact(hostname: "duckduckgo.com")]
    }

    func isSERPSettingsFeatureOn() -> Bool {
        return mockIsSERPSettingsFeatureOn
    }

    func storeSERPSettings(settings: [String: Any]) {
        wasStoreSettingsCalled = true

        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [])
            do {
                try keyValueStore?.set(data, forKey: SERPSettingsConstants.serpSettingsStorage)
            } catch {
                eventMapper?.fire(.keyValueStoreWriteError, error: error)
            }
        } catch {
            eventMapper?.fire(.serializationFailed, error: error)
        }
    }

    func reset() {
        wasStoreSettingsCalled = false
    }
}

// Simple mock implementations for AI providers
#if os(iOS)
final class MockAIChatSettingsProvider: AIChatSettingsProvider {
    var aiChatURL: URL = URL(string: "https://duckduckgo.com/ai")!
    var isAIChatEnabled: Bool = false
    var sessionTimerInMinutes: Int = 30
    var isAIChatAddressBarUserSettingsEnabled: Bool = false
    var isAIChatSearchInputUserSettingsEnabled: Bool = false
    var isAIChatBrowsingMenuUserSettingsEnabled: Bool = false
    var isAIChatVoiceSearchUserSettingsEnabled: Bool = false
    var isAIChatTabSwitcherUserSettingsEnabled: Bool = false
    var isAIChatFullModeEnabled: Bool = false
    var isAutomaticContextAttachmentEnabled: Bool = false

    func enableAIChat(enable: Bool) {
        isAIChatEnabled = enable
    }
    func enableAIChatBrowsingMenuUserSettings(enable: Bool) {}
    func enableAIChatAddressBarUserSettings(enable: Bool) {}
    func enableAIChatVoiceSearchUserSettings(enable: Bool) {}
    func enableAIChatTabSwitcherUserSettings(enable: Bool) {}
    func enableAIChatSearchInputUserSettings(enable: Bool) {}
    func enableAIChatFullModeSetting(enable: Bool) {}
    func enableAutomaticContextAttachment(enable: Bool) {}
}
#endif

#if os(macOS)
import Combine

final class MockAIChatPreferencesStorage: AIChatPreferencesStorage {
    private let isAIFeaturesEnabledSubject = PassthroughSubject<Bool, Never>()
    private let showShortcutOnNewTabPageSubject = PassthroughSubject<Bool, Never>()
    private let showShortcutInApplicationMenuSubject = PassthroughSubject<Bool, Never>()
    private let showShortcutInAddressBarSubject = PassthroughSubject<Bool, Never>()
    private let showShortcutInAddressBarWhenTypingSubject = PassthroughSubject<Bool, Never>()
    private let openAIChatInSidebarSubject = PassthroughSubject<Bool, Never>()
    private let shouldAutomaticallySendPageContextSubject = PassthroughSubject<Bool, Never>()
    private let showSearchAndDuckAIToggleSubject = PassthroughSubject<Bool, Never>()

    var isAIFeaturesEnabled: Bool = false
    var isAIFeaturesEnabledPublisher: AnyPublisher<Bool, Never> {
        isAIFeaturesEnabledSubject.eraseToAnyPublisher()
    }

    var showShortcutOnNewTabPage: Bool = false
    var showShortcutOnNewTabPagePublisher: AnyPublisher<Bool, Never> {
        showShortcutOnNewTabPageSubject.eraseToAnyPublisher()
    }

    var showShortcutInApplicationMenu: Bool = false
    var showShortcutInApplicationMenuPublisher: AnyPublisher<Bool, Never> {
        showShortcutInApplicationMenuSubject.eraseToAnyPublisher()
    }

    var showShortcutInAddressBar: Bool = false
    var showShortcutInAddressBarPublisher: AnyPublisher<Bool, Never> {
        showShortcutInAddressBarSubject.eraseToAnyPublisher()
    }

    var showShortcutInAddressBarWhenTyping: Bool = false
    var showShortcutInAddressBarWhenTypingPublisher: AnyPublisher<Bool, Never> {
        showShortcutInAddressBarWhenTypingSubject.eraseToAnyPublisher()
    }

    var openAIChatInSidebar: Bool = false
    var openAIChatInSidebarPublisher: AnyPublisher<Bool, Never> {
        openAIChatInSidebarSubject.eraseToAnyPublisher()
    }

    var shouldAutomaticallySendPageContext: Bool = false
    var shouldAutomaticallySendPageContextPublisher: AnyPublisher<Bool, Never> {
        shouldAutomaticallySendPageContextSubject.eraseToAnyPublisher()
    }

    var showSearchAndDuckAIToggle: Bool = true
    var showSearchAndDuckAITogglePublisher: AnyPublisher<Bool, Never> {
        showSearchAndDuckAIToggleSubject.eraseToAnyPublisher()
    }

    var userDidSeeToggleOnboarding: Bool = false

    func reset() {
        isAIFeaturesEnabled = false
        showShortcutOnNewTabPage = false
        showShortcutInApplicationMenu = false
        showShortcutInAddressBar = false
        showShortcutInAddressBarWhenTyping = false
        openAIChatInSidebar = false
        shouldAutomaticallySendPageContext = false
        showSearchAndDuckAIToggle = true
        userDidSeeToggleOnboarding = false
    }
}
#endif
