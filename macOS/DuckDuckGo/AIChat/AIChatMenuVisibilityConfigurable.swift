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
import Combine
import PrivacyConfig

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
    /// should be presented to the user when typing.
    ///
    /// - Returns: `true` if the address bar shortcut when typing should be displayed; otherwise, `false`.
    var shouldDisplayAddressBarShortcutWhenTyping: Bool { get }

    /// This property validates user settings to determine if the shortcut
    /// should be presented to the user.
    ///
    /// - Returns: `true` if the application menu shortcut should be displayed; otherwise, `false`.
    var shouldDisplayApplicationMenuShortcut: Bool { get }

    /// This property validates user settings to determine if the Duck.ai submenu
    /// should be presented in the more options (hamburger) menu.
    ///
    /// - Returns: `true` if the more options menu shortcut should be displayed; otherwise, `false`.
    var shouldDisplayMoreOptionsMenuShortcut: Bool { get }

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

    /// This property validates user settings and the `selectionContext` subfeature to determine
    /// whether the "Attach to Duck.ai" context-menu action should be presented to the user.
    ///
    /// - Returns: `true` if the attach-selection menu action should be displayed; otherwise, `false`.
    var shouldDisplaySelectionContextMenuItem: Bool { get }

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

        return isAIChatEnabledRemotely && isAIChatEnabledLocally
    }

    var shouldDisplayNewTabPageShortcut: Bool {
        shouldDisplayAnyAIChatFeature && storage.showShortcutOnNewTabPage
    }

    var shouldDisplaySummarizationMenuItem: Bool {
        shouldDisplayAnyAIChatFeature
    }

    var shouldDisplayTranslationMenuItem: Bool {
        shouldDisplayAnyAIChatFeature
    }

    var shouldDisplaySelectionContextMenuItem: Bool {
        shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.aiChatSelectionContext)
    }

    var shouldDisplayApplicationMenuShortcut: Bool {
        return shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.aiChatMainMenuShortcut)
    }

    var shouldDisplayMoreOptionsMenuShortcut: Bool {
        return shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.aiChatMoreOptionsMenuShortcut)
    }

    var shouldDisplayAddressBarShortcut: Bool {
        shouldDisplayAnyAIChatFeature && storage.showShortcutInAddressBar
    }

    var shouldDisplayAddressBarShortcutWhenTyping: Bool {
        return shouldDisplayAnyAIChatFeature && storage.showShortcutInAddressBarWhenTyping
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
        let storagePublishers: [AnyPublisher<Bool, Never>] = [
            storage.isAIFeaturesEnabledPublisher.removeDuplicates().eraseToAnyPublisher(),
            storage.showShortcutOnNewTabPagePublisher.removeDuplicates().eraseToAnyPublisher(),
            storage.showShortcutInApplicationMenuPublisher.removeDuplicates().eraseToAnyPublisher(),
            storage.showShortcutInAddressBarPublisher.removeDuplicates().eraseToAnyPublisher(),
            storage.showShortcutInAddressBarWhenTypingPublisher.removeDuplicates().eraseToAnyPublisher(),
            storage.openAIChatInSidebarPublisher.removeDuplicates().eraseToAnyPublisher(),
            storage.shouldAutomaticallySendPageContextPublisher.removeDuplicates().eraseToAnyPublisher(),
            storage.showSearchAndDuckAITogglePublisher.removeDuplicates().eraseToAnyPublisher(),
        ]

        let mainMenuShortcutFlagPublisher = featureFlagger.updatesPublisher
            .map { [weak self] in self?.featureFlagger.isFeatureOn(.aiChatMainMenuShortcut) ?? false }
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()

        let moreOptionsMenuShortcutFlagPublisher = featureFlagger.updatesPublisher
            .map { [weak self] in self?.featureFlagger.isFeatureOn(.aiChatMoreOptionsMenuShortcut) ?? false }
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()

        Publishers.MergeMany(storagePublishers)
            .map { _ in () }
            .merge(with: mainMenuShortcutFlagPublisher)
            .merge(with: moreOptionsMenuShortcutFlagPublisher)
            .sink { [weak self] in
                self?.valuesChangedPublisher.send()
            }.store(in: &cancellables)
    }
}
