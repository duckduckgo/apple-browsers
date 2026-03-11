//
//  AIChatPreferences.swift
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
import Foundation
import PixelKit
import PrivacyConfig

final class AIChatPreferences: ObservableObject {

    private var storage: AIChatPreferencesStorage
    private var cancellables = Set<AnyCancellable>()
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private var windowControllersManager: WindowControllersManagerProtocol
    private let featureFlagger: FeatureFlagger
    private let duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging

    init(storage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
         aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable = Application.appDelegate.aiChatMenuConfiguration,
         windowControllersManager: WindowControllersManagerProtocol = Application.appDelegate.windowControllersManager,
         featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger,
         duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging = LocalDuckAIChromeButtonsVisibilityManager()) {
        self.storage = storage
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.windowControllersManager = windowControllersManager
        self.featureFlagger = featureFlagger
        self.duckAIChromeButtonsVisibilityManager = duckAIChromeButtonsVisibilityManager

        isAIFeaturesEnabled = storage.isAIFeaturesEnabled
        showShortcutOnNewTabPage = storage.showShortcutOnNewTabPage
        showShortcutInApplicationMenu = storage.showShortcutInApplicationMenu
        showShortcutInAddressBarWhenTyping = storage.showShortcutInAddressBarWhenTyping
        showShortcutInAddressBar = storage.showShortcutInAddressBar
        openAIChatInSidebar = storage.openAIChatInSidebar
        shouldAutomaticallySendPageContext = storage.shouldAutomaticallySendPageContext
        showSearchAndDuckAIToggle = storage.showSearchAndDuckAIToggle
        showDuckAIButtonInTabBar = !duckAIChromeButtonsVisibilityManager.isHidden(.duckAI)
        showSidebarButtonInTabBar = !duckAIChromeButtonsVisibilityManager.isHidden(.sidebar)

        subscribeToShowInApplicationMenuSettingsChanges()
        subscribeToDuckAIChromeButtonsVisibilityChanges()
    }

    func subscribeToShowInApplicationMenuSettingsChanges() {
        storage.isAIFeaturesEnabledPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.isAIFeaturesEnabled, onWeaklyHeld: self)
            .store(in: &cancellables)

        storage.showShortcutOnNewTabPagePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.showShortcutOnNewTabPage, onWeaklyHeld: self)
            .store(in: &cancellables)

        storage.showShortcutInApplicationMenuPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.showShortcutInApplicationMenu, onWeaklyHeld: self)
            .store(in: &cancellables)

        storage.showShortcutInAddressBarPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.showShortcutInAddressBar, onWeaklyHeld: self)
            .store(in: &cancellables)

        storage.showShortcutInAddressBarWhenTypingPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.showShortcutInAddressBarWhenTyping, onWeaklyHeld: self)
            .store(in: &cancellables)

        storage.openAIChatInSidebarPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.openAIChatInSidebar, onWeaklyHeld: self)
            .store(in: &cancellables)

        storage.showSearchAndDuckAITogglePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.showSearchAndDuckAIToggle, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    // Options visibility

    var shouldShowAIFeatures: Bool {
        aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature
    }

    var shouldShowPageContextToggle: Bool {
        featureFlagger.isFeatureOn(.aiChatPageContext)
    }

    var shouldShowNewTabPageToggle: Bool {
        featureFlagger.isFeatureOn(.newTabPageOmnibar)
    }

    var shouldShowHideAIGeneratedImagesSection: Bool {
        featureFlagger.isFeatureOn(.showHideAIGeneratedImagesSection)
    }

    var shouldShowSearchAndDuckAIToggleOption: Bool {
        featureFlagger.isFeatureOn(.aiChatOmnibarToggle)
    }

    var shouldShowTabBarButtonVisibilityOptions: Bool {
        featureFlagger.isFeatureOn(.aiChatChromeSidebar)
    }

    var isPageContextToggleDisabled: Bool {
        if shouldShowTabBarButtonVisibilityOptions {
            return false
        }
        return !showShortcutInAddressBar || !openAIChatInSidebar
    }

    // Properties for managing the current state of AI Chat preference options

    @Published var isAIFeaturesEnabled: Bool {
        didSet { storage.isAIFeaturesEnabled = isAIFeaturesEnabled }
    }

    var isAIFeaturesEnabledPublisher: AnyPublisher<Bool, Never> {
        $isAIFeaturesEnabled.eraseToAnyPublisher()
    }

    @Published var showShortcutOnNewTabPage: Bool {
        didSet { storage.showShortcutOnNewTabPage = showShortcutOnNewTabPage }
    }

    @Published var showShortcutInAddressBarWhenTyping: Bool {
        didSet { storage.showShortcutInAddressBarWhenTyping = showShortcutInAddressBarWhenTyping }
    }

    @Published var showShortcutInApplicationMenu: Bool {
        didSet { storage.showShortcutInApplicationMenu = showShortcutInApplicationMenu }
    }

    @Published var showShortcutInAddressBar: Bool {
        didSet { storage.showShortcutInAddressBar = showShortcutInAddressBar }
    }

    @Published var openAIChatInSidebar: Bool {
        didSet { storage.openAIChatInSidebar = openAIChatInSidebar }
    }

    @Published var shouldAutomaticallySendPageContext: Bool {
        didSet { storage.shouldAutomaticallySendPageContext = shouldAutomaticallySendPageContext }
    }

    @Published var showSearchAndDuckAIToggle: Bool {
        didSet { storage.showSearchAndDuckAIToggle = showSearchAndDuckAIToggle }
    }

    @Published var showDuckAIButtonInTabBar: Bool {
        didSet { duckAIChromeButtonsVisibilityManager.setHidden(!showDuckAIButtonInTabBar, for: .duckAI) }
    }

    @Published var showSidebarButtonInTabBar: Bool {
        didSet { duckAIChromeButtonsVisibilityManager.setHidden(!showSidebarButtonInTabBar, for: .sidebar) }
    }

    @MainActor func openLearnMoreLink() {
        windowControllersManager.show(url: URL.aiChatApproachToAI, source: .ui, newTab: true, selected: true)
    }

    @MainActor func openAIChatLink() {
        NSApp.delegateTyped.aiChatTabOpener.openNewAIChat(in: .currentTab)
    }

    @MainActor func openSearchAssistSettings() {
        windowControllersManager.show(url: URL.aiChatSettings, source: .ui, newTab: true, selected: true)
    }

    private func subscribeToDuckAIChromeButtonsVisibilityChanges() {
        NotificationCenter.default.publisher(for: .duckAIChromeButtonsVisibilityChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let shouldShowDuckAIButton = !duckAIChromeButtonsVisibilityManager.isHidden(.duckAI)
                let shouldShowSidebarButton = !duckAIChromeButtonsVisibilityManager.isHidden(.sidebar)

                if showDuckAIButtonInTabBar != shouldShowDuckAIButton {
                    showDuckAIButtonInTabBar = shouldShowDuckAIButton
                }
                if showSidebarButtonInTabBar != shouldShowSidebarButton {
                    showSidebarButtonInTabBar = shouldShowSidebarButton
                }
            }
            .store(in: &cancellables)
    }
}
