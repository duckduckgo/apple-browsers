//
//  DuckAISettingsStatePixel.swift
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

import AIChat
import PrivacyConfig
import PixelKit
import UIKit

/// Daily snapshot of the Duck.ai settings, mirroring macOS `aichat_settings_state_macos`.
struct DuckAISettingsStatePixel: PixelKit.Event {

    enum OpenDuckAITabs: String {
        case none = "0"
        case one = "1"
        case twoOrMore = "2+"

        init(count: Int) {
            switch count {
            case ...0: self = .none
            case 1: self = .one
            default: self = .twoOrMore
            }
        }
    }

    let duckAIEnabled: Bool
    let addressBarToggle: Bool
    let tabBarButton: Bool
    let defaultMode: DefaultOmnibarMode
    let openDuckAITabs: OpenDuckAITabs

    var name: String { "aichat_settings_state" }

    var parameters: [String: String]? {
        [
            "duckai_enabled": String(duckAIEnabled),
            "addressbar_toggle": String(addressBarToggle),
            "tabbar_button": String(tabBarButton),
            "default_mode": defaultMode.rawValue,
            "duckai_tabs_open": openDuckAITabs.rawValue,
        ]
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

@MainActor
struct DuckAISettingsStatePixelReporter {

    private let settings: AIChatSettingsProvider
    private let featureFlagger: FeatureFlagger
    private let isPad: Bool
    private let openDuckAITabCount: () -> Int
    private let pixelFiring: PixelFiring?

    init(settings: AIChatSettingsProvider,
         featureFlagger: FeatureFlagger,
         isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad,
         openDuckAITabCount: @escaping () -> Int,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.settings = settings
        self.featureFlagger = featureFlagger
        self.isPad = isPad
        self.openDuckAITabCount = openDuckAITabCount
        self.pixelFiring = pixelFiring
    }

    func fireDaily() {
        pixelFiring?.fire(currentState, frequency: .daily)
    }

    var currentState: DuckAISettingsStatePixel {
        DuckAISettingsStatePixel(
            duckAIEnabled: settings.isAIChatEnabled,
            addressBarToggle: settings.isAIChatSearchInputUserSettingsEnabled,
            tabBarButton: isTabBarDuckAIButtonAvailable,
            defaultMode: settings.defaultOmnibarMode,
            openDuckAITabs: DuckAISettingsStatePixel.OpenDuckAITabs(count: openDuckAITabCount())
        )
    }

    /// The same rule the tabs bar uses to show its Duck.ai menu button or chip.
    private var isTabBarDuckAIButtonAvailable: Bool {
        guard isPad else { return false }
        let isShortcutEnabled = settings.isAIChatTabBarUserSettingsEnabled
        return DuckAIChromeShortcutVisibility.isChromeMenuButtonVisible(featureFlagger: featureFlagger, isTabBarShortcutEnabled: isShortcutEnabled)
            || DuckAIChromeShortcutVisibility.isChromeButtonVisible(featureFlagger: featureFlagger,
                                                                    isTabBarShortcutEnabled: isShortcutEnabled,
                                                                    isDuckAIButtonVisible: settings.isAIChatTabBarDuckAIButtonVisible,
                                                                    isContextualSheetButtonVisible: settings.isAIChatTabBarContextualSheetButtonVisible)
    }
}
