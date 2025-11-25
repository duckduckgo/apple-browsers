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
import os.log
import Core
import Persistence
import BrowserServicesKit
import AIChat
import RemoteMessaging

protocol NewAddressBarPickerDisplayValidating {
    func shouldDisplayNewAddressBarPicker() -> Bool
}

struct NewAddressBarPickerDisplayValidator: NewAddressBarPickerDisplayValidating {
    
    // MARK: - Dependencies
    
    private let aiChatSettings: AIChatSettingsProvider
    private let featureFlagger: FeatureFlagger
    private let experimentalAIChatManager: ExperimentalAIChatManager
    private let appSettings: AppSettings
    private let pickerStorage: NewAddressBarPickerStorageReading
    private let searchExperienceOnboardingProvider: OnboardingSearchExperienceProvider

    // MARK: - Initialization
    
    init(
        aiChatSettings: AIChatSettingsProvider,
        featureFlagger: FeatureFlagger,
        experimentalAIChatManager: ExperimentalAIChatManager,
        appSettings: AppSettings,
        pickerStorage: NewAddressBarPickerStorage,
        searchExperienceOnboardingProvider: OnboardingSearchExperienceProvider
    ) {
        self.aiChatSettings = aiChatSettings
        self.featureFlagger = featureFlagger
        self.experimentalAIChatManager = experimentalAIChatManager
        self.appSettings = appSettings
        self.pickerStorage = pickerStorage
        self.searchExperienceOnboardingProvider = searchExperienceOnboardingProvider
    }
    
    // MARK: - Public Interface
    
    func shouldDisplayNewAddressBarPicker() -> Bool {
        /// https://app.asana.com/1/137249556945/task/1211152753855410?focus=true

        Logger.addressBarPicker.info("Checking picker display conditions...")

        /// Do not display during automated UI runs
        /// https://app.asana.com/1/137249556945/project/414709148257752/task/1211474728965506?focus=true
        guard !isRunningUITests else { return false }
        Logger.addressBarPicker.info("✓ Not running UI Tests")

        guard isMainDuckAIEnabled else { return false }
        Logger.addressBarPicker.info("✓ Main DuckAI is enabled")
        
        guard isFeatureFlagEnabled else { return false }
        Logger.addressBarPicker.info("✓ Feature flag is enabled")

        guard canShowPickerAfterOnboardingSelection else { return false }
        Logger.addressBarPicker.info("✓ Passes onboarding selection check")

        guard !isAIChatSearchInputEnabled else { return false }
        Logger.addressBarPicker.info("✓ AIChat address bar is disabled")

        guard !isAddressBarPositionBottom else { return false }
        Logger.addressBarPicker.info("✓ Address bar position is not bottom")

        guard !hasForceChoiceBeenShown else { return false }
        Logger.addressBarPicker.info("✓ Force choice has not been shown yet")

        Logger.addressBarPicker.info("All conditions passed - picker can be shown")
        return true
    }

    // MARK: - Show Criteria Variables
    
    private var isMainDuckAIEnabled: Bool {
        aiChatSettings.isAIChatEnabled
    }
    
    private var isFeatureFlagEnabled: Bool {
        featureFlagger.isFeatureOn(.showAIChatAddressBarChoiceScreen)
    }
    
    // MARK: - Exclusion Criteria Variables
    
    private var isAIChatSearchInputEnabled: Bool {
        aiChatSettings.isAIChatSearchInputUserSettingsEnabled
    }
    
    private var isAddressBarPositionBottom: Bool {
        appSettings.currentAddressBarPosition.isBottom
    }

    private var hasForceChoiceBeenShown: Bool {
        pickerStorage.hasBeenShown
    }

    private var canShowPickerAfterOnboardingSelection: Bool {
        guard featureFlagger.isFeatureOn(.onboardingSearchExperience) else { return true }
        guard searchExperienceOnboardingProvider.didMakeChoiceDuringOnboarding else { return true }
        return searchExperienceOnboardingProvider.didEnableAIChatSearchInputDuringOnboarding
    }

    private var isRunningUITests: Bool {
        ProcessInfo.isRunningUITests
    }
}

// MARK: - Storage

protocol NewAddressBarPickerStorageReading {
    var hasBeenShown: Bool { get }
}

protocol NewAddressBarPickerStorageWriting {
    func markAsShown()
}

typealias NewAddressBarPickerStorage = NewAddressBarPickerStorageReading & NewAddressBarPickerStorageWriting

struct NewAddressBarPickerStore: NewAddressBarPickerStorage {
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
    
    func reset() {
        keyValueStore.removeObject(forKey: Key.hasBeenShown)
    }
}

extension ProcessInfo {
    static var isRunningUITests: Bool {
        Self.processInfo.arguments.contains("isRunningUITests")
    }
}
