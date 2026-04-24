//
//  NewTabPageOmnibarConfigProvider.swift
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

import AIChat
import AppKit
import Combine
import FeatureFlags
import NewTabPage
import PrivacyConfig
import os.log
import Persistence
import PixelKit
import Common

protocol NewTabPageAIChatShortcutSettingProviding: AnyObject {
    var isAIChatShortcutEnabled: Bool { get set }
    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> { get }
    var isAIChatSettingVisible: Bool { get }
    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> { get }
}

final class NewTabPageAIChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding {
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private var aiChatPreferencesStorage: AIChatPreferencesStorage

    init(
        aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
        aiChatPreferencesStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage()
    ) {
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.aiChatPreferencesStorage = aiChatPreferencesStorage
    }

    var isAIChatShortcutEnabled: Bool {
        get {
            aiChatMenuConfiguration.shouldDisplayNewTabPageShortcut
        }
        set {
            aiChatPreferencesStorage.showShortcutOnNewTabPage = newValue
        }
    }

    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> {
        aiChatMenuConfiguration.valuesChangedPublisher
            .compactMap { [weak self] in
                self?.aiChatMenuConfiguration
            }
            .map(\.shouldDisplayNewTabPageShortcut)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var isAIChatSettingVisible: Bool {
        aiChatPreferencesStorage.isAIFeaturesEnabled
    }

    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> {
        aiChatPreferencesStorage.isAIFeaturesEnabledPublisher.eraseToAnyPublisher()
    }
}

final class NewTabPageOmnibarConfigProvider: NewTabPageOmnibarConfigProviding {
    private enum Key: String {
        case newTabPageOmnibarMode
    }

    private enum LegacyKey: String {
        /// Previously-used per-NTP key. Migrated into `AIChatPreferencesPersisting.selectedModelId`
        /// (shared with the native omnibar) on first init after the unification, then removed.
        case newTabPageSelectedModelId
    }

    private enum Constants: Int {
        case maxNumberOfPopoverPresentations = 5
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let aiChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding
    private let featureFlagger: FeatureFlagger
    private let firePixel: (PixelKitEvent) -> Void
    private var aiChatPreferencesPersistor: AIChatPreferencesPersisting
    private let showCustomizePopoverSubject = PassthroughSubject<Bool, Never>()
    private let modeSubject = PassthroughSubject<NewTabPageDataModel.OmnibarMode, Never>()
    @Published private var hasExcessChats = false
    private var aiChatsProviderCancellable: AnyCancellable?

    init(keyValueStore: ThrowingKeyValueStoring,
         aiChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding,
         featureFlagger: FeatureFlagger,
         aiChatPreferencesPersistor: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
         firePixel: @escaping (PixelKitEvent) -> Void = { PixelKit.fire($0, frequency: .dailyAndStandard) }) {
        self.keyValueStore = keyValueStore
        self.aiChatShortcutSettingProvider = aiChatShortcutSettingProvider
        self.featureFlagger = featureFlagger
        self.aiChatPreferencesPersistor = aiChatPreferencesPersistor
        self.firePixel = firePixel

        Self.migrateLegacySelectedModelIdIfNeeded(from: keyValueStore, into: &self.aiChatPreferencesPersistor)
    }

    @MainActor
    var mode: NewTabPageDataModel.OmnibarMode {
        get {
            guard isAIChatShortcutEnabled && isAIChatSettingVisible else {
                return .search
            }
            do {
                if let rawValue = try keyValueStore.object(forKey: Key.newTabPageOmnibarMode.rawValue) as? String,
                   let mode = NewTabPageDataModel.OmnibarMode(rawValue: rawValue) {
                    return mode
                }
            } catch {
                Logger.newTabPageOmnibar.error("Failed to retrieve omnibar mode from keyValueStore: \(error.localizedDescription)")
            }
            return .search
        }
        set {
            firePixel(NewTabPagePixel.omnibarModeChanged(mode: newValue == .search ? .search : .duckAI))
            do {
                try keyValueStore.set(newValue.rawValue, forKey: Key.newTabPageOmnibarMode.rawValue)
            } catch {
                Logger.newTabPageOmnibar.error("Failed to set omnibar mode in keyValueStore: \(error.localizedDescription)")
            }
            modeSubject.send(newValue)
        }
    }

    var isAIChatShortcutEnabled: Bool {
        get {
            aiChatShortcutSettingProvider.isAIChatShortcutEnabled
        }
        set {
            aiChatShortcutSettingProvider.isAIChatShortcutEnabled = newValue
        }
    }

    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> {
        aiChatShortcutSettingProvider.isAIChatShortcutEnabledPublisher
    }

    var isAIChatSettingVisible: Bool {
        aiChatShortcutSettingProvider.isAIChatSettingVisible
    }

    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> {
        aiChatShortcutSettingProvider.isAIChatSettingVisiblePublisher
    }

    var modePublisher: AnyPublisher<NewTabPageDataModel.OmnibarMode, Never> {
        modeSubject.eraseToAnyPublisher()
    }

    var isAIChatRecentChatsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpRecentChats)
    }

    var isAIChatToolsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpChatTools)
    }

    var selectedModelId: String? {
        get {
            aiChatPreferencesPersistor.selectedModelId
        }
        set {
            guard newValue != aiChatPreferencesPersistor.selectedModelId else { return }
            aiChatPreferencesPersistor.selectedModelId = newValue
            if newValue != nil {
                PixelKit.fire(AIChatPixel.aiChatNtpModelSelected, frequency: .dailyAndCount, includeAppVersionParameter: true)
            }
        }
    }

    var selectedModelIdPublisher: AnyPublisher<String?, Never> {
        aiChatPreferencesPersistor.selectedModelIdPublisher
    }

    var selectedModelShortName: String? {
        get {
            aiChatPreferencesPersistor.selectedModelShortName
        }
        set {
            aiChatPreferencesPersistor.selectedModelShortName = newValue
        }
    }

    var isReasoningEffortEnabled: Bool {
        // Reasoning effort depends on the model picker being available — if tools aren't
        // enabled, there's no model picker and reasoning has nothing to attach to.
        isAIChatToolsEnabled && featureFlagger.isFeatureOn(.aiChatOmnibarReasoningEffort)
    }

    var selectedReasoningEffort: String? {
        get {
            guard isReasoningEffortEnabled else { return nil }
            return aiChatPreferencesPersistor.selectedReasoningEffort
        }
        set {
            guard isReasoningEffortEnabled else { return }
            guard newValue != aiChatPreferencesPersistor.selectedReasoningEffort else { return }
            aiChatPreferencesPersistor.selectedReasoningEffort = newValue
            if newValue != nil {
                PixelKit.fire(AIChatPixel.aiChatNtpReasoningEffortSelected, frequency: .dailyAndCount, includeAppVersionParameter: true)
            }
        }
    }

    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> {
        aiChatPreferencesPersistor.selectedReasoningEffortPublisher
    }

    var isImageGenerationEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpImageGeneration)
    }

    var isWebSearchEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpWebSearch)
    }

    var showCustomizePopover: Bool {
        get {
            // We no longer present the tooltip
            return false
        }
        set {
        }
    }

    var showViewAllAiChats: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpRecentChats)
            && featureFlagger.isFeatureOn(.aiChatNtpViewAllChats)
            && hasExcessChats
    }

    var showViewAllAiChatsPublisher: AnyPublisher<Bool, Never> {
        $hasExcessChats
            .map { [weak self] hasExcess in
                guard let self else { return false }
                return self.featureFlagger.isFeatureOn(.aiChatNtpRecentChats)
                    && self.featureFlagger.isFeatureOn(.aiChatNtpViewAllChats)
                    && hasExcess
            }
            .eraseToAnyPublisher()
    }

    func configure(aiChatsProvider: NewTabPageOmnibarAiChatsProviding) {
        aiChatsProviderCancellable = aiChatsProvider.hasExcessChatsPublisher
            .sink { [weak self] hasExcess in
                guard let self else { return }
                self.hasExcessChats = hasExcess
            }
    }

    /// One-time migration: copy the old NTP-only model id into the shared `AIChatPreferencesPersisting`
    /// store when the shared value is absent, then drop the legacy key so subsequent launches skip the work.
    ///
    /// The legacy NTP store never cached a short name, so on the upgrade path we seed it with the
    /// model id as a placeholder. This keeps the native omnibar's model picker visible on first
    /// launch post-upgrade (the picker is hidden when both `models` and `selectedModelShortName`
    /// are empty). The real short name replaces the placeholder once the models fetch completes.
    private static func migrateLegacySelectedModelIdIfNeeded(
        from keyValueStore: ThrowingKeyValueStoring,
        into persistor: inout AIChatPreferencesPersisting
    ) {
        let legacyKey = LegacyKey.newTabPageSelectedModelId.rawValue
        guard let legacyValue = try? keyValueStore.object(forKey: legacyKey) as? String else {
            return
        }
        if persistor.selectedModelId == nil {
            persistor.selectedModelId = legacyValue
            if persistor.selectedModelShortName == nil {
                persistor.selectedModelShortName = legacyValue
            }
        }
        try? keyValueStore.removeObject(forKey: legacyKey)
    }

}
