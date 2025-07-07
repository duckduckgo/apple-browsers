//
//  AIChatSettingsProvider.swift
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

#if os(iOS)
import Foundation

public protocol AIChatSettingsProvider {
    /// The URL used to open AI Chat in the `AIChatViewController`.
    var aiChatURL: URL { get }

    /// The user state for AI chat overall.
    var isAIChatEnabled: Bool { get }

    /// Remote config for keep session subfeature
    var sessionTimerInMinutes: Int { get }

    /// The user settings state for the AI Chat browsing address bar.
    var isAIChatAddressBarUserSettingsEnabled: Bool { get }

    /// The user settings state for the AI Chat Search Input
    var isAIChatSearchInputUserSettingsEnabled: Bool { get }

    /// The user settings state for the AI Chat browsing menu icon.
    var isAIChatBrowsingMenuUserSettingsEnabled: Bool { get }

    /// The user settings state for the AI Chat voice search
    var isAIChatVoiceSearchUserSettingsEnabled: Bool { get }

    /// The user settings state for the AI Chat in tab manager
    var isAIChatTabSwitcherUserSettingsEnabled: Bool { get }

    /// Updates the user settings state for AI Chat overall.
    func enableAIChat(enable: Bool)

    /// Updates the user settings state for the AI Chat browsing menu.
    func enableAIChatBrowsingMenuUserSettings(enable: Bool)

    /// Updates the user settings state for the AI Chat address bar.
    func enableAIChatAddressBarUserSettings(enable: Bool)

    /// Updates the user settings state for the AI Chat voice search
    func enableAIChatVoiceSearchUserSettings(enable: Bool)

    /// Updates the user settings state for the AI Chat voice search
    func enableAIChatTabSwitcherUserSettings(enable: Bool)

    /// Updates the user settings state for the AI Chat Search Input
    func enableAIChatSearchInputUserSettings(enable: Bool)
}
#endif
