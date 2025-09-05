//
//  NewAddressBarPickerDisplayValidator.swift
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
import Core
import Persistence
import BrowserServicesKit
import AIChat

protocol NewAddressBarPickerDisplayValidating {
    func shouldDisplayNewAddressBarPicker() -> Bool
    func markPickerDisplayAsSeen()
}

struct NewAddressBarPickerDisplayValidator: NewAddressBarPickerDisplayValidating {
    
    // MARK: - Dependencies
    
    private let aiChatSettings: AIChatSettingsProvider
    private let tutorialSettings: TutorialSettings
    private let featureFlagger: FeatureFlagger
    private let experimentalAIChatManager: ExperimentalAIChatManager
    private let appSettings: AppSettings
    private let pickerStorage: NewAddressBarPickerStorage
    
    // MARK: - Initialization
    
    init(
        aiChatSettings: AIChatSettingsProvider,
        tutorialSettings: TutorialSettings,
        featureFlagger: FeatureFlagger,
        experimentalAIChatManager: ExperimentalAIChatManager,
        appSettings: AppSettings,
        pickerStorage: NewAddressBarPickerStorage
    ) {
        self.aiChatSettings = aiChatSettings
        self.tutorialSettings = tutorialSettings
        self.featureFlagger = featureFlagger
        self.experimentalAIChatManager = experimentalAIChatManager
        self.appSettings = appSettings
        self.pickerStorage = pickerStorage
    }
    
    // MARK: - Public Interface
    
    func shouldDisplayNewAddressBarPicker() -> Bool {
        /// https://app.asana.com/1/137249556945/task/1211152753855410?focus=true
        /// Check all show criteria first
        guard isMainDuckAIEnabled else { return false }
        guard isOnboardingCompletedOrSkipped else { return false }
        guard isFeatureFlagEnabled else { return false }
        
        /// Check all exclusion criteria
        guard !isDuckAIAddressBarDisabled else { return false }
        guard !isNewToggleExperimentEnabled else { return false }
        guard !hasForceChoiceBeenShown else { return false }
        guard !isLaunchedFromExternalSource else { return false }

        return true
    }

    func markPickerDisplayAsSeen() {
        pickerStorage.markAsShown()
    }

    // MARK: - Show Criteria Variables
    
    /// Check if main Duck.ai is enabled (default is true)
    private var isMainDuckAIEnabled: Bool {
        return aiChatSettings.isAIChatEnabled
    }
    
    /// Check if user has completed or skipped onboarding
    private var isOnboardingCompletedOrSkipped: Bool {
        return tutorialSettings.hasSeenOnboarding
    }
    
    /// Check if the feature flag for showing the address bar choice screen is enabled
    private var isFeatureFlagEnabled: Bool {
        return featureFlagger.isFeatureOn(.showAIChatAddressBarChoiceScreen)
    }
    
    // MARK: - Exclusion Criteria Variables
    
    /// Check if Duck.ai shortcut in address bar is disabled
    private var isDuckAIAddressBarDisabled: Bool {
        return !aiChatSettings.isAIChatAddressBarUserSettingsEnabled
    }
    
    /// Check if user has already enabled the new toggle experiment
    private var isNewToggleExperimentEnabled: Bool {
        return experimentalAIChatManager.isExperimentalAIChatSettingsEnabled
    }
    
    /// Check if force-choice has already been shown once
    private var hasForceChoiceBeenShown: Bool {
        return pickerStorage.hasBeenShown
    }
    
    /// Check if app was launched from external source (links, widgets, notifications, Siri shortcuts)
    private var isLaunchedFromExternalSource: Bool {
        return false
    }
}

// MARK: - Storage

struct NewAddressBarPickerStorage {
    
    private let keyValueStore: KeyValueStoring
    
    private enum Key {
        static let hasBeenShown = "aichat.storage.newAddressBarPickerShown"
    }
    
    init(keyValueStore: KeyValueStoring = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults()) {
        self.keyValueStore = keyValueStore
    }
    
    var hasBeenShown: Bool {
        return (keyValueStore.object(forKey: Key.hasBeenShown) as? Bool) ?? false
    }
    
    func markAsShown() {
        keyValueStore.set(true, forKey: Key.hasBeenShown)
    }
}
