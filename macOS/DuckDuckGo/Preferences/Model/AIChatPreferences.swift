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
import CombineExtensions
import Foundation
import PixelKit
import PrivacyConfig
import SERPSettings
import SwiftUI

final class AIChatPreferences: ObservableObject {

    private var storage: AIChatPreferencesStorage
    private var cancellables = Set<AnyCancellable>()
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private var windowControllersManager: WindowControllersManagerProtocol
    private let featureFlagger: FeatureFlagger
    private let duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging
    // Lazy: built on first use, not during early/transient inits when the store isn't ready yet.
    private lazy var serpSettings: SERPSettingsProviding = SERPSettingsProvider()

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
        subscribeToSERPSettingsChanges()
    }

    // Refresh the Search Assist / Hide AI Images pickers when the SERP changes them on the web side.
    private func subscribeToSERPSettingsChanges() {
        NotificationCenter.default.publisher(for: .serpSettingsDidReceiveWebUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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

    var shouldShowDuckAiSettingsLink: Bool {
        featureFlagger.isFeatureOn(.aiChatSettingsLinkInAiFeatures)
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

    var shouldShowNativeAIControls: Bool {
        featureFlagger.isFeatureOn(.aiFeaturesNativeControls)
    }

    // Native SERP AI settings (Search Assist / Hide AI Images), backed by the shared SERP settings store.

    var searchAssistFrequencyBinding: Binding<SearchAssistFrequency> {
        Binding(
            get: { self.serpSettings.searchAssistFrequency },
            set: { newValue in
                guard newValue != self.serpSettings.searchAssistFrequency else { return }
                self.objectWillChange.send()
                self.serpSettings.searchAssistFrequency = newValue
                PixelKit.fire(Self.searchAssistPixel(for: newValue),
                              frequency: .dailyAndCount,
                              includeAppVersionParameter: true)
            }
        )
    }

    var hideAIImagesBinding: Binding<HideAIImagesOption> {
        Binding(
            get: { HideAIImagesOption(hidden: self.serpSettings.hideAIGeneratedImages) },
            set: { newValue in
                guard newValue.hidden != self.serpSettings.hideAIGeneratedImages else { return }
                self.objectWillChange.send()
                self.serpSettings.hideAIGeneratedImages = newValue.hidden
                PixelKit.fire(newValue.hidden ? AIChatPixel.aiFeaturesHideImagesOn : .aiFeaturesHideImagesOff,
                              frequency: .dailyAndCount,
                              includeAppVersionParameter: true)
            }
        )
    }

    // Duck.ai on/off, exposed as a dropdown in the native-controls layout. Fires the global-toggle
    // pixel only on user-driven changes (not external/storage-driven updates to isAIFeaturesEnabled).
    var duckAIEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.isAIFeaturesEnabled },
            set: { newValue in
                guard newValue != self.isAIFeaturesEnabled else { return }
                self.isAIFeaturesEnabled = newValue
                PixelKit.fire(newValue ? AIChatPixel.aiChatSettingsGlobalToggleTurnedOn : .aiChatSettingsGlobalToggleTurnedOff,
                              frequency: .dailyAndCount,
                              includeAppVersionParameter: true)
            }
        )
    }

    /// Maps a Search Assist frequency to its value-in-name AI Features pixel.
    private static func searchAssistPixel(for frequency: SearchAssistFrequency) -> AIChatPixel {
        switch frequency {
        case .never: return .aiFeaturesSearchAssistNever
        case .onDemand: return .aiFeaturesSearchAssistOnDemand
        case .sometimes: return .aiFeaturesSearchAssistSometimes
        case .often: return .aiFeaturesSearchAssistOften
        }
    }

    // Duck.ai-only; `isAIFeaturesEnabled` is the legacy name (kept to avoid an app-wide rename).
    private var isDuckAIEnabled: Bool {
        get { isAIFeaturesEnabled }
        set { isAIFeaturesEnabled = newValue }
    }

    var isAllAIDisabled: Bool {
        !isDuckAIEnabled
            && serpSettings.searchAssistFrequency == .never
            && serpSettings.hideAIGeneratedImages
    }

    @MainActor func disableAllAI() {
        objectWillChange.send()
        isDuckAIEnabled = false
        serpSettings.searchAssistFrequency = .never
        serpSettings.hideAIGeneratedImages = true
        PixelKit.fire(AIChatPixel.aiFeaturesDisabled,
                      frequency: .dailyAndCount,
                      includeAppVersionParameter: true)
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

    @MainActor func openHideAIGeneratedImagesLearnMore() {
        windowControllersManager.show(url: URL.hideAIGeneratedImagesLearnMore, source: .ui, newTab: true, selected: true)
    }

    /// Opens duck.ai in a new tab and triggers the Duck.ai Settings modal once the page
    /// has wired up its message subscriptions.
    @MainActor func openDuckAiSettings() {
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(with: .openSettings, behavior: .newTab(selected: true))
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
