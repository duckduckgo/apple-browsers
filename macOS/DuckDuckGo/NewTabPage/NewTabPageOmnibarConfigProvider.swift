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
import NewTabPage
import os.log
import Persistence
import PixelKit

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

    private let keyValueStore: ThrowingKeyValueStoring
    private let aiChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding
    private let firePixel: (PixelKitEvent) -> Void

    init(keyValueStore: ThrowingKeyValueStoring,
         aiChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding,
         firePixel: @escaping (PixelKitEvent) -> Void = { PixelKit.fire($0, frequency: .dailyAndStandard) }) {
        self.keyValueStore = keyValueStore
        self.aiChatShortcutSettingProvider = aiChatShortcutSettingProvider
        self.firePixel = firePixel
    }

    @MainActor
    var mode: NewTabPageDataModel.OmnibarMode {
        get {
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
}
