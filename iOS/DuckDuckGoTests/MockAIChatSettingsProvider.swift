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
    public var isAIChatAddressBarUserSettingsEnabled: Bool
    public var isAIChatBrowsingMenuUserSettingsEnabled: Bool
    public var isAIChatFeatureEnabled: Bool
    public var isAIChatBrowsingMenubarShortcutFeatureEnabled: Bool
    public var isAIChatAddressBarShortcutFeatureEnabled: Bool
    public var isAIChatVoiceSearchFeatureEnabled: Bool
    public var isAIChatVoiceSearchUserSettingsEnabled: Bool
    public var isAIChatTabSwitcherFeatureEnabled: Bool
    public var isAIChatTabSwitcherUserSettingsEnabled: Bool

    public init(aiChatURL: URL = URL(string: "https://example.com")!,
                isAIChatAddressBarUserSettingsEnabled: Bool = false,
                isAIChatBrowsingMenuUserSettingsEnabled: Bool = false,
                isAIChatFeatureEnabled: Bool = false,
                isAIChatBrowsingMenubarShortcutFeatureEnabled: Bool = false,
                isAIChatAddressBarShortcutFeatureEnabled: Bool = false,
                isAIChatVoiceSearchFeatureEnabled: Bool = false,
                isAIChatVoiceSearchUserSettingsEnabled: Bool = false,
                isAIChatTabSwitcherFeatureEnabled: Bool = false,
                isAIChatTabSwitcherUserSettingsEnabled: Bool = false) {

        self.aiChatURL = aiChatURL
        self.isAIChatAddressBarUserSettingsEnabled = isAIChatAddressBarUserSettingsEnabled
        self.isAIChatBrowsingMenuUserSettingsEnabled = isAIChatBrowsingMenuUserSettingsEnabled
        self.isAIChatFeatureEnabled = isAIChatFeatureEnabled
        self.isAIChatBrowsingMenubarShortcutFeatureEnabled = isAIChatBrowsingMenubarShortcutFeatureEnabled
        self.isAIChatAddressBarShortcutFeatureEnabled = isAIChatAddressBarShortcutFeatureEnabled
        self.isAIChatVoiceSearchFeatureEnabled = isAIChatVoiceSearchFeatureEnabled
        self.isAIChatVoiceSearchUserSettingsEnabled = isAIChatVoiceSearchUserSettingsEnabled
        self.isAIChatTabSwitcherFeatureEnabled = isAIChatTabSwitcherFeatureEnabled
        self.isAIChatTabSwitcherUserSettingsEnabled = isAIChatTabSwitcherUserSettingsEnabled
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
        isAIChatTabSwitcherFeatureEnabled = enable
    }

}
