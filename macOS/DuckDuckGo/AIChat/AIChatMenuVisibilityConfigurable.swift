//
//  AIChatMenuVisibilityConfigurable.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Combine

protocol AIChatMenuVisibilityConfigurable {

    /// Indicates whether any AI Chat feature should be displayed to the user.
    ///
    /// This property checks both remote setting and local global switch value to determine
    /// if any of the AI Chat-related features should be visible in the UI.
    ///
    /// - Returns: `true` if any AI Chat feature should be shown; otherwise, `false`.
    var shouldDisplayAnyAIChatFeature: Bool { get }

    /// This property validates user settings to determine if the shortcut
    /// should be presented to the user.
    ///
    /// - Returns: `true` if the New Tab Page omnibar shortcut should be displayed; otherwise, `false`.
    var shouldDisplayNewTabPageShortcut: Bool { get }

    /// This property validates user settings to determine if the shortcut
    /// should be presented to the user.
    ///
    /// - Returns: `true` if the address bar shortcut should be displayed; otherwise, `false`.
    var shouldDisplayAddressBarShortcut: Bool { get }

    /// This property validates user settings to determine if the shortcut
    /// should be presented to the user.
    ///
    /// - Returns: `true` if the application menu shortcut should be displayed; otherwise, `false`.
    var shouldDisplayApplicationMenuShortcut: Bool { get }

    /// This property determines whether AI Chat should open in the sidebar.
    ///
    /// - Returns: `true` if AI Chat should open in the sidebar; otherwise, `false`.
    var shouldOpenAIChatInSidebar: Bool { get }

    /// This property determines whether websites should automatically send page context to the AI Chat sidebar.
    ///
    /// - Returns: `true` if AI Chat should open in the sidebar; otherwise, `false`.
    var shouldAutomaticallySendPageContext: Bool { get }

    /// This property is used for telemetry.
    ///
    /// - Returns: The value of `shouldAutomaticallySendPageContext` if the feature flag is enabled, otherwise it returns `nil`.
    var shouldAutomaticallySendPageContextTelemetryValue: Bool? { get }

    /// This property validates user settings to determine if the text summarization
    /// feature should be presented to the user.
    ///
    /// - Returns: `true` if the text summarization menu action should be displayed; otherwise, `false`.
    var shouldDisplaySummarizationMenuItem: Bool { get }

    /// This property validates user settings to determine if the text translation
    /// feature should be presented to the user.
    ///
    /// - Returns: `true` if the text translation menu action should be displayed; otherwise, `false`.
    var shouldDisplayTranslationMenuItem: Bool { get }

    /// A publisher that emits a value when either the `shouldDisplayApplicationMenuShortcut`  settings, backed by storage, are changed.
    ///
    /// This allows subscribers to react to changes in the visibility settings of the application menu
    /// and toolbar shortcuts.
    ///
    /// - Returns: A `PassthroughSubject` that emits `Void` when the values change.
    var valuesChangedPublisher: PassthroughSubject<Void, Never> { get }
}

final class AIChatMenuConfiguration: AIChatMenuVisibilityConfigurable {

    enum ShortcutType {
        case applicationMenu
        case toolbar
    }

    private var cancellables = Set<AnyCancellable>()
    private var storage: AIChatPreferencesStorage
    private let remoteSettings: AIChatRemoteSettingsProvider
    private let featureFlagger: FeatureFlagger

    var valuesChangedPublisher = PassthroughSubject<Void, Never>()

    var shouldDisplayAnyAIChatFeature: Bool {
        let isAIChatEnabledRemotely = remoteSettings.isAIChatEnabled
        let isAIChatEnabledLocally = storage.isAIFeaturesEnabled

        if featureFlagger.isFeatureOn(.aiChatGlobalSwitch) {
            return isAIChatEnabledRemotely && isAIChatEnabledLocally
        } else {
            return isAIChatEnabledRemotely
        }
    }

    var shouldDisplayNewTabPageShortcut: Bool {
        shouldDisplayAnyAIChatFeature && storage.showShortcutOnNewTabPage
    }

    var shouldDisplaySummarizationMenuItem: Bool {
        shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.aiChatTextSummarization) && shouldDisplayApplicationMenuShortcut
    }

    var shouldDisplayTranslationMenuItem: Bool {
        shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.aiChatTextTranslation) && shouldDisplayApplicationMenuShortcut
    }

    var shouldDisplayApplicationMenuShortcut: Bool {
        shouldDisplayAnyAIChatFeature && storage.showShortcutInApplicationMenu
    }

    var shouldDisplayAddressBarShortcut: Bool {
        shouldDisplayAnyAIChatFeature && storage.showShortcutInAddressBar
    }

    var shouldOpenAIChatInSidebar: Bool {
        shouldDisplayAnyAIChatFeature && storage.openAIChatInSidebar
    }

    var shouldAutomaticallySendPageContext: Bool {
        shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.aiChatPageContext) && storage.shouldAutomaticallySendPageContext
    }

    var shouldAutomaticallySendPageContextTelemetryValue: Bool? {
        guard featureFlagger.isFeatureOn(.aiChatPageContext) else {
            return nil
        }
        return shouldAutomaticallySendPageContext
    }

    init(storage: AIChatPreferencesStorage, remoteSettings: AIChatRemoteSettingsProvider, featureFlagger: FeatureFlagger) {
        self.storage = storage
        self.remoteSettings = remoteSettings
        self.featureFlagger = featureFlagger

        self.subscribeToValuesChanged()
    }

    private func subscribeToValuesChanged() {
        Publishers.Merge6(
            storage.isAIFeaturesEnabledPublisher.removeDuplicates(),
            storage.showShortcutOnNewTabPagePublisher.removeDuplicates(),
            storage.showShortcutInApplicationMenuPublisher.removeDuplicates(),
            storage.showShortcutInAddressBarPublisher.removeDuplicates(),
            storage.openAIChatInSidebarPublisher.removeDuplicates(),
            storage.shouldAutomaticallySendPageContextPublisher.removeDuplicates()
        )
        .sink { [weak self] _ in
            self?.valuesChangedPublisher.send()
        }.store(in: &cancellables)
    }
}
