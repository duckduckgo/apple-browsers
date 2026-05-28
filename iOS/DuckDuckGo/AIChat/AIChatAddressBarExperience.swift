//
//  AIChatAddressBarExperience.swift
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

import UIKit
import AIChat
import Core
import PrivacyConfig

protocol UserInterfaceIdiomProviding {
    var userInterfaceIdiom: UIUserInterfaceIdiom { get }
}

struct SystemUserInterfaceIdiomProvider: UserInterfaceIdiomProviding {
    var userInterfaceIdiom: UIUserInterfaceIdiom {
        UIDevice.current.userInterfaceIdiom
    }
}

protocol LargeWidthProviding {
    var isLargeWidth: Bool { get }
}

extension AppWidthObserver: LargeWidthProviding {}

protocol AIChatAddressBarExperienceProviding {
    var shouldShowDuckAIAddressBarButton: Bool { get }
    var shouldShowModeToggle: Bool { get }
    var shouldUseExperimentalEditingState: Bool { get }
    var isIPadAIToggleExperienceEnabled: Bool { get }
}

struct AIChatAddressBarExperience: AIChatAddressBarExperienceProviding {

    private let featureFlagger: FeatureFlagger
    private let aiChatSettings: AIChatSettingsProvider
    private let userInterfaceIdiomProvider: UserInterfaceIdiomProviding
    private let largeWidthProvider: LargeWidthProviding

    init(featureFlagger: FeatureFlagger,
         aiChatSettings: AIChatSettingsProvider,
         userInterfaceIdiomProvider: UserInterfaceIdiomProviding = SystemUserInterfaceIdiomProvider(),
         largeWidthProvider: LargeWidthProviding = AppWidthObserver.shared) {
        self.featureFlagger = featureFlagger
        self.aiChatSettings = aiChatSettings
        self.userInterfaceIdiomProvider = userInterfaceIdiomProvider
        self.largeWidthProvider = largeWidthProvider
    }

    var isIPadAIToggleExperienceEnabled: Bool {
        userInterfaceIdiomProvider.userInterfaceIdiom == .pad
            && featureFlagger.isFeatureOn(.iPadAIToggle)
    }

    private var isIPadChromeShortcutInPlay: Bool {
        userInterfaceIdiomProvider.userInterfaceIdiom == .pad
            && featureFlagger.isFeatureOn(.aiChatChromeShortcutIPad)
    }

    var shouldShowDuckAIAddressBarButton: Bool {
        if isIPadChromeShortcutInPlay {
            return DuckAIChromeShortcutVisibility.isAddressBarButtonVisibleOnIPad(
                isLargeWidth: largeWidthProvider.isLargeWidth,
                isAIChatNavigationBarUserSettingsEnabled: aiChatSettings.isAIChatNavigationBarUserSettingsEnabled
            )
        }
        return aiChatSettings.isAIChatAddressBarUserSettingsEnabled
    }

    var shouldShowModeToggle: Bool {
        isIPadAIToggleExperienceEnabled
            && aiChatSettings.isAIChatSearchInputUserSettingsEnabled
    }

    var shouldUseExperimentalEditingState: Bool {
        aiChatSettings.isAIChatSearchInputUserSettingsEnabled
            && !isIPadAIToggleExperienceEnabled
    }
}
