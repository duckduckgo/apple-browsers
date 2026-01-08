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
import PrivacyConfig

@MainActor
protocol DataClearingSettingsViewModelDelegate: AnyObject {
    func navigateToFireproofSites()
    func navigateToAutoClearData()
    func presentFireConfirmation()
}

@MainActor
final class DataClearingSettingsViewModel: ObservableObject {
    
    // MARK: - Observers
    
    private var appDataClearingObserver: Any?
    
    // MARK: - Dependencies

    private let featureFlagger: FeatureFlagger
    private let appSettings: AppSettings
    private let aiChatSettings: AIChatSettingsProvider
    private let animator: FireButtonAnimator
    private let fireproofing: Fireproofing
    
    // MARK: - Delegate
    
    weak var delegate: DataClearingSettingsViewModelDelegate?
        
    // MARK: - Published State
    
    @Published private var fireButtonAnimation: FireButtonAnimationType
    @Published private var autoclearDataEnabled: Bool = false
    @Published private var fireproofedSitesCount: Int = 0
    
    // MARK: - Elements Visibility
    
    var newUIEnabled: Bool {
        featureFlagger.isFeatureOn(.granularFireButtonOptions)
    }
    
    var showAIChatsToggle: Bool {
        if newUIEnabled { return false }
        return aiChatSettings.isAIChatEnabled && featureFlagger.isFeatureOn(.duckAiDataClearing)
    }
    
    // MARK: - Elements Content

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
    
    var fireproofedSitesSubtitle: String? {
        guard newUIEnabled else {
            return nil
        }
        return UserText.settingsFireproofedSitesSubtitle(withCount: fireproofedSitesCount)
    }
    
    var autoClearTitle: String {
        newUIEnabled ? UserText.settingsAutomaticDataClearing : UserText.settingsClearData
    }
    
    var footnoteText: String {
        let shouldIncludeAIChat = appSettings.autoClearAIChatHistory

        return shouldIncludeAIChat ? UserText.settingsDataClearingForgetAllWithAiChatFootnote : UserText.settingsDataClearingForgetAllFootnote
    }
    
    var autoClearAccessibilityLabel: String {
        autoclearDataEnabled
        ? UserText.autoClearAccessoryOn
        : UserText.autoClearAccessoryOff
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
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         aiChatSettings: AIChatSettingsProvider,
         fireproofing: Fireproofing,
         delegate: DataClearingSettingsViewModelDelegate) {
        self.appSettings = appSettings
        self.featureFlagger = featureFlagger
        self.aiChatSettings = aiChatSettings
        self.animator = FireButtonAnimator(appSettings: appSettings)
        self.fireButtonAnimation = appSettings.currentFireButtonAnimation
        self.fireproofing = fireproofing
        self.delegate = delegate
        refreshFireproofedSitesCount()
        updateAutoclearDataEnabled()
        setupObserver()
    }
    
    deinit {
        if let token = appDataClearingObserver {
            NotificationCenter.default.removeObserver(token)
        }
        appDataClearingObserver = nil
    }
    
    // MARK: - Actions
    
    func openFireproofSites() {
        delegate?.navigateToFireproofSites()
    }
    
    func openAutoClearData() {
        delegate?.navigateToAutoClearData()
    }
    
    func presentFireConfirmation() {
        DailyPixel.fireDailyAndCount(pixel: .forgetAllPressedSettings,
                                     pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes)
        delegate?.presentFireConfirmation()
    }
    
    func refreshFireproofedSitesCount() {
        fireproofedSitesCount = fireproofing.allowedDomains.count
    }
    
    
    // MARK: - Private Helpers
    
    private func setupObserver() {
        appDataClearingObserver = NotificationCenter.default.addObserver(forName: AppUserDefaults.Notifications.appDataClearingUpdated,
                                                                         object: nil,
                                                                         queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.updateAutoclearDataEnabled()
            }
        }
    }
    
    private func updateAutoclearDataEnabled() {
        autoclearDataEnabled = !appSettings.autoClearAction.isEmpty
    }
}
