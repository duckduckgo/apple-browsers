//
//  DataClearingSettingsViewModel.swift
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
import SwiftUI
import Core
import AIChat

@MainActor
final class DataClearingSettingsViewModel: ObservableObject {
    
    // MARK: - Dependencies

    private lazy var featureFlagger = AppDependencyProvider.shared.featureFlagger
    private let appSettings: AppSettings
    private let aiChatSettings: AIChatSettingsProvider
    private let animator: FireButtonAnimator
    private let fireproofing: Fireproofing
    
    // MARK: - Delegate
        
    // MARK: - Published State
    
    @Published var fireButtonAnimation: FireButtonAnimationType
    
    // MARK: - Elements Visibility
    
    var newUIEnabled: Bool {
        featureFlagger.isFeatureOn(.granularFireButtonOptions)
    }
    
    var useImprovedPicker: Bool {
        featureFlagger.isFeatureOn(.mobileCustomization)
    }
    
    var showAIChatsToggle: Bool {
        if newUIEnabled { return false }
        return aiChatSettings.isAIChatEnabled && featureFlagger.isFeatureOn(.duckAiDataClearing)
    }
    
    // MARK: - Elements Cnntent

    var clearDataButtonTitle: String {
        if newUIEnabled {
            return UserText.settingsClearBrowsingData
        }
        let shouldIncludeAIChat = appSettings.autoClearAIChatHistory
        return shouldIncludeAIChat ? UserText.actionForgetAllWithAIChat : UserText.actionForgetAll
    }
    
    var fireproofedSitesTitle: String {
        newUIEnabled ? UserText.settingsFireproofedSites : UserText.settingsFireproofSites
    }
    
    var fireproofedSitesSubtitle: String {
        UserText.settingsFireproofedSitesSubtitle(withCount: fireproofedSitesCount)
    }
    
    var autoClearTitle: String {
        newUIEnabled ? UserText.settingsAutomaticDataClearing : UserText.settingsClearData
    }
    
    var footnoteText: String {
        let shouldIncludeAIChat = appSettings.autoClearAIChatHistory

        return shouldIncludeAIChat ? UserText.settingsDataClearingForgetAllWithAiChatFootnote : UserText.settingsDataClearingForgetAllFootnote
    }
    
    // MARK: - Bindings
    
    var fireButtonAnimationBinding: Binding<FireButtonAnimationType> {
        Binding<FireButtonAnimationType>(
            get: { self.fireButtonAnimation },
            set: {
                Pixel.fire(pixel: .settingsFireButtonSelectorPressed)
                self.appSettings.currentFireButtonAnimation = $0
                self.fireButtonAnimation = $0
                NotificationCenter.default.post(name: AppUserDefaults.Notifications.currentFireButtonAnimationChange, object: self)
                self.animator.animate {
                    // no op
                } onTransitionCompleted: {
                    // no op
                } completion: {
                    // no op
                }
            }
        )
    }
    
    // MARK: - Initialization
    
    init(appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         aiChatSettings: AIChatSettingsProvider,
         fireproofing: Fireproofing) {
        self.appSettings = appSettings
        self.aiChatSettings = aiChatSettings
        self.animator = FireButtonAnimator(appSettings: appSettings)
        self.fireButtonAnimation = appSettings.currentFireButtonAnimation
        self.fireproofing = fireproofing
    }
    
    // MARK: - Actions
    
    
    // MARK: - Private Helpers
    
    private var fireproofedSitesCount: Int {
        fireproofing.allowedDomains.count
    }
}
