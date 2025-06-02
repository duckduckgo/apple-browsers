//
//  MockAIChatSettingsProvider.swift
//  DuckDuckGo
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
import AIChat

public class MockAIChatSettingsProvider: AIChatSettingsProvider {

    public var aiChatURL: URL
    public var isAIChatEnabled: Bool
    public var isAIChatAddressBarUserSettingsEnabled: Bool
    public var isAIChatBrowsingMenuUserSettingsEnabled: Bool
    public var isAIChatAddressBarShortcutFeatureEnabled: Bool
    public var isAIChatVoiceSearchUserSettingsEnabled: Bool
    public var isAIChatTabSwitcherUserSettingsEnabled: Bool
    public var sessionTimerInMinutes: Int

    public init(aiChatURL: URL = URL(string: "https://example.com")!,
                isAIChatEnabled: Bool = false,
                isAIChatAddressBarUserSettingsEnabled: Bool = false,
                isAIChatBrowsingMenuUserSettingsEnabled: Bool = false,
                isAIChatBrowsingMenubarShortcutFeatureEnabled: Bool = false,
                isAIChatAddressBarShortcutFeatureEnabled: Bool = false,
                isAIChatVoiceSearchUserSettingsEnabled: Bool = false,
                isAIChatTabSwitcherUserSettingsEnabled: Bool = false,
                sessionTimerInMinutes: Int = 60) {

        self.aiChatURL = aiChatURL
        self.isAIChatEnabled = isAIChatEnabled
        self.isAIChatAddressBarUserSettingsEnabled = isAIChatAddressBarUserSettingsEnabled
        self.isAIChatBrowsingMenuUserSettingsEnabled = isAIChatBrowsingMenuUserSettingsEnabled
        self.isAIChatAddressBarShortcutFeatureEnabled = isAIChatAddressBarShortcutFeatureEnabled
        self.isAIChatVoiceSearchUserSettingsEnabled = isAIChatVoiceSearchUserSettingsEnabled
        self.isAIChatTabSwitcherUserSettingsEnabled = isAIChatTabSwitcherUserSettingsEnabled
        self.sessionTimerInMinutes = sessionTimerInMinutes
    }
    
    public func enableAIChatBrowsingMenuUserSettings(enable: Bool) {
        isAIChatBrowsingMenuUserSettingsEnabled = enable
    }
    
    public func enableAIChatAddressBarUserSettings(enable: Bool) {
        isAIChatAddressBarUserSettingsEnabled = enable
    }

    public func enableAIChatVoiceSearchUserSettings(enable: Bool) {
        isAIChatVoiceSearchUserSettingsEnabled = enable
    }

    public func enableAIChatTabSwitcherUserSettings(enable: Bool) {
        isAIChatTabSwitcherUserSettingsEnabled = enable
    }

    public func enableAIChat(enable: Bool) {
        isAIChatEnabled = enable
    }

}
