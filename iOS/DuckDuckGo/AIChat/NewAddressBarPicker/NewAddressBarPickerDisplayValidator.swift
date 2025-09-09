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
import RemoteMessaging

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
    private let launchSourceManager: LaunchSourceManaging
    private let remoteMessageStore: RemoteMessagingStoring

    // MARK: - Initialization
    
    init(
        aiChatSettings: AIChatSettingsProvider,
        tutorialSettings: TutorialSettings,
        featureFlagger: FeatureFlagger,
        experimentalAIChatManager: ExperimentalAIChatManager,
        appSettings: AppSettings,
        pickerStorage: NewAddressBarPickerStorage,
        launchSourceManager: LaunchSourceManaging,
        remoteMessageStore: RemoteMessagingStoring
    ) {
        self.aiChatSettings = aiChatSettings
        self.tutorialSettings = tutorialSettings
        self.featureFlagger = featureFlagger
        self.experimentalAIChatManager = experimentalAIChatManager
        self.appSettings = appSettings
        self.pickerStorage = pickerStorage
        self.launchSourceManager = launchSourceManager
        self.remoteMessageStore = remoteMessageStore
    }
    
    // MARK: - Public Interface
    
    func shouldDisplayNewAddressBarPicker() -> Bool {
        /// https://app.asana.com/1/137249556945/task/1211152753855410?focus=true
        guard isMainDuckAIEnabled else { return false }
        guard isOnboardingCompletedOrSkipped else { return false }
        guard isFeatureFlagEnabled else { return false }
        
        guard !isDuckAIAddressBarDisabled else { return false }
        guard !isNewToggleExperimentEnabled else { return false }
        guard !hasForceChoiceBeenShown else { return false }
        guard !isLaunchedFromExternalSource else { return false }
        guard !hasInteractedWithAddressBarRemoteMessage else { return false }

        return true
    }

    func markPickerDisplayAsSeen() {
        pickerStorage.markAsShown()
    }

    // MARK: - Show Criteria Variables
    
    private var isMainDuckAIEnabled: Bool {
        aiChatSettings.isAIChatEnabled
    }
    
    private var isOnboardingCompletedOrSkipped: Bool {
        tutorialSettings.hasSeenOnboarding
    }
    
    private var isFeatureFlagEnabled: Bool {
        featureFlagger.isFeatureOn(.showAIChatAddressBarChoiceScreen)
    }
    
    // MARK: - Exclusion Criteria Variables
    
    private var isDuckAIAddressBarDisabled: Bool {
        !aiChatSettings.isAIChatAddressBarUserSettingsEnabled
    }
    
    private var isNewToggleExperimentEnabled: Bool {
        experimentalAIChatManager.isExperimentalAIChatSettingsEnabled
    }

    private var hasForceChoiceBeenShown: Bool {
        pickerStorage.hasBeenShown
    }

    private var isLaunchedFromExternalSource: Bool {
        launchSourceManager.source != .standard
    }

    private var hasInteractedWithAddressBarRemoteMessage: Bool {
        let dismissedMessageIDs = remoteMessageStore.fetchDismissedRemoteMessageIDs()
        return dismissedMessageIDs.contains("search_duck_ai_announcement")
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
    
    func reset() {
        keyValueStore.removeObject(forKey: Key.hasBeenShown)
    }
}
