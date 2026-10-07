//
//  AIChatSettingsStatePixelSender.swift
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

import AIChat
import FeatureFlags_macOS
import Foundation
import NewTabPage
import PixelKit
import PrivacyConfig

/// Fires `AIChatPixel.aiChatSettingsState` once a day with the Duck.ai settings as they stand.
final class AIChatSettingsStatePixelSender {

    private let preferencesStorage: AIChatPreferencesStorage
    private let menuConfiguration: AIChatMenuVisibilityConfigurable
    private let chromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging
    private let featureFlagger: FeatureFlagger
    private let isGlobalShortcutEnabled: () -> Bool
    private let isMenuBarIconVisible: () -> Bool
    private let isNewTabPageSearchBoxVisible: () -> Bool
    private let newTabPageOmnibarMode: () -> NewTabPageDataModel.OmnibarMode
    private let pixelFiring: PixelFiring?

    init(preferencesStorage: AIChatPreferencesStorage,
         menuConfiguration: AIChatMenuVisibilityConfigurable,
         chromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging,
         featureFlagger: FeatureFlagger,
         isGlobalShortcutEnabled: @escaping () -> Bool,
         isMenuBarIconVisible: @escaping () -> Bool,
         isNewTabPageSearchBoxVisible: @escaping () -> Bool,
         newTabPageOmnibarMode: @escaping () -> NewTabPageDataModel.OmnibarMode,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.preferencesStorage = preferencesStorage
        self.menuConfiguration = menuConfiguration
        self.chromeButtonsVisibilityManager = chromeButtonsVisibilityManager
        self.featureFlagger = featureFlagger
        self.isGlobalShortcutEnabled = isGlobalShortcutEnabled
        self.isMenuBarIconVisible = isMenuBarIconVisible
        self.isNewTabPageSearchBoxVisible = isNewTabPageSearchBoxVisible
        self.newTabPageOmnibarMode = newTabPageOmnibarMode
        self.pixelFiring = pixelFiring
    }

    func firePixel() {
        pixelFiring?.fire(AIChatPixel.aiChatSettingsState(duckAIEnabled: preferencesStorage.isAIFeaturesEnabled,
                                                          addressBarToggle: preferencesStorage.showSearchAndDuckAIToggle,
                                                          tabBarButton: !chromeButtonsVisibilityManager.isHidden(.duckAI),
                                                          globalShortcut: isGlobalShortcutEnabled(),
                                                          menuBarIcon: isMenuBarIconVisible(),
                                                          newTabPage: newTabPageState),
                          frequency: .daily)
    }

    /// Without the omnibar flag the New Tab Page has no search box, so its settings mean nothing.
    private var newTabPageState: AIChatNewTabPageSettingsState? {
        guard featureFlagger.isFeatureOn(.newTabPageOmnibar) else { return nil }
        let isDuckAIShortcutEnabled = menuConfiguration.shouldDisplayNewTabPageShortcut
        return AIChatNewTabPageSettingsState(
            isSearchBoxVisible: isNewTabPageSearchBoxVisible(),
            isDuckAIShortcutEnabled: isDuckAIShortcutEnabled,
            // The search box falls back to search whenever Duck.ai isn't offered there.
            isDuckAIModeSelected: isDuckAIShortcutEnabled && newTabPageOmnibarMode() == .ai
        )
    }
}
