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
import BrowserServicesKit
import Combine
import Foundation
import PixelKit

final class AIChatPreferences: ObservableObject {
    static let shared = AIChatPreferences()
    private var storage: AIChatPreferencesStorage
    private var cancellables = Set<AnyCancellable>()
    private let learnMoreURL = URL(string: "https://duckduckgo.com/duckduckgo-help-pages/aichat/")!
    private let searchAssistSettingsURL = URL(string: "https://duckduckgo.com/settings#aifeatures")!
    private var windowControllersManager: WindowControllersManager
    private let featureFlagger: FeatureFlagger

    init(storage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
         windowControllersManager: WindowControllersManager = Application.appDelegate.windowControllersManager,
         featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger) {
        self.storage = storage
        self.windowControllersManager = windowControllersManager
        self.featureFlagger = featureFlagger

        showShortcutInApplicationMenu = storage.showShortcutInApplicationMenu
        showShortcutInAddressBar = storage.showShortcutInAddressBar
        openAIChatInSidebar = storage.openAIChatInSidebar

        subscribeToShowInApplicationMenuSettingsChanges()
    }

    func subscribeToShowInApplicationMenuSettingsChanges() {
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

        storage.openAIChatInSidebarPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.openAIChatInSidebar, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    var shouldShowOpenAIChatInSidebarToggle: Bool {
        featureFlagger.isFeatureOn(.aiChatSidebar)
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

    @MainActor func openLearnMoreLink() {
        windowControllersManager.show(url: learnMoreURL, source: .ui, newTab: true)
    }

    @MainActor func openAIChatLink() {
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab()
    }

    @MainActor func openSearchAssistSettings() {
        windowControllersManager.show(url: searchAssistSettingsURL, source: .ui, newTab: true)
    }
}
