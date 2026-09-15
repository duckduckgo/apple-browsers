//
//  NewTabPageCustomizationModel.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation
import PixelKit

final class NewTabPageCustomizationModel: ObservableObject {

    @Published var isFavoritesSectionVisible: Bool {
        didSet {
            guard oldValue != isFavoritesSectionVisible else { return }
            persistor.isFavoritesSectionVisible = isFavoritesSectionVisible
            pixelFiring?.fire(NewTabPageCustomizationPixel.favoritesToggled)
        }
    }

    @Published var isMessagesSectionVisible: Bool {
        didSet {
            guard oldValue != isMessagesSectionVisible else { return }
            persistor.isMessagesSectionVisible = isMessagesSectionVisible
            pixelFiring?.fire(NewTabPageCustomizationPixel.messagesToggled)
        }
    }

    @Published var isKeyboardShownOnNewTab: Bool {
        didSet {
            guard oldValue != isKeyboardShownOnNewTab else { return }
            keyboardSettings.onNewTab = isKeyboardShownOnNewTab
            pixelFiring?.fire(NewTabPageCustomizationPixel.keyboardToggled)
        }
    }

    var onAllSettingsSelected: (() -> Void)?

    private let pixelFiring: (any PixelKitFiring)?

    private var persistor: NewTabPageCustomizationPersisting
    private var keyboardSettings: KeyboardSettings

    init(persistor: NewTabPageCustomizationPersisting = NewTabPageCustomizationStore(),
         keyboardSettings: KeyboardSettings = KeyboardSettings(),
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
        self.persistor = persistor
        self.keyboardSettings = keyboardSettings

        isFavoritesSectionVisible = persistor.isFavoritesSectionVisible
        isMessagesSectionVisible = persistor.isMessagesSectionVisible
        isKeyboardShownOnNewTab = keyboardSettings.onNewTab
    }

    func reportOpening() {
        pixelFiring?.fire(NewTabPageCustomizationPixel.opened, frequency: .dailyAndCount)
    }

    func selectAllSettings() {
        pixelFiring?.fire(NewTabPageCustomizationPixel.allSettingsOpened)
        onAllSettingsSelected?()
    }
}
