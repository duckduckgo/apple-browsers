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
            pixelFiring?.fire(NewTabPageCustomizationPixel.favoritesToggled(enabled: isFavoritesSectionVisible), frequency: .dailyAndCount)
        }
    }

    @Published var isMessagesSectionVisible: Bool {
        didSet {
            guard oldValue != isMessagesSectionVisible else { return }
            persistor.isMessagesSectionVisible = isMessagesSectionVisible
            pixelFiring?.fire(NewTabPageCustomizationPixel.messagesToggled, frequency: .dailyAndCount)
        }
    }

    @Published var isKeyboardShownOnNewTab: Bool {
        didSet {
            guard oldValue != isKeyboardShownOnNewTab else { return }
            keyboardSettings.onNewTab = isKeyboardShownOnNewTab
            pixelFiring?.fire(NewTabPageCustomizationPixel.keyboardToggled(enabled: isKeyboardShownOnNewTab), frequency: .dailyAndCount)
        }
    }

    @Published var isProceduralBackgroundEnabled: Bool {
        didSet {
            var settings = backgroundStore.settings
            settings.isProcedural = isProceduralBackgroundEnabled
            backgroundStore.settings = settings
        }
    }

    @Published var backgroundSeedDraft: String

    var isBackgroundSeedValid: Bool { parsedBackgroundSeed != nil }

    private var parsedBackgroundSeed: UInt64? {
        let text = backgroundSeedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.allSatisfy({ (48 ... 57).contains($0) }) else { return nil }
        return UInt64(text)
    }

    private let backgroundStore: NewTabPageBackgroundStore
    private let makeBackgroundSeed: () -> UInt64

    func applyBackgroundSeed() {
        guard let seed = parsedBackgroundSeed else { return }
        backgroundSeedDraft = String(seed)
        backgroundStore.settings = NewTabPageBackgroundSettings(isProcedural: true, seed: seed)
        isProceduralBackgroundEnabled = true
    }

    func randomizeBackgroundSeed() {
        let currentSeed = backgroundStore.settings.seed
        let newSeed = makeBackgroundSeed()
        backgroundSeedDraft = String(newSeed == currentSeed ? newSeed &+ 1 : newSeed)
        applyBackgroundSeed()
    }

    var onAllSettingsSelected: (() -> Void)?

    private let pixelFiring: (any PixelKitFiring)?

    private var persistor: NewTabPageCustomizationPersisting
    private var keyboardSettings: KeyboardSettings

    init(persistor: NewTabPageCustomizationPersisting = NewTabPageCustomizationStore(),
         keyboardSettings: KeyboardSettings = KeyboardSettings(),
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared,
         backgroundStore: NewTabPageBackgroundStore = NewTabPageBackgroundStore(),
         makeBackgroundSeed: @escaping () -> UInt64 = { UInt64.random(in: .min ... .max) }) {
        self.backgroundStore = backgroundStore
        self.makeBackgroundSeed = makeBackgroundSeed
        let backgroundSettings = backgroundStore.settings
        isProceduralBackgroundEnabled = backgroundSettings.isProcedural
        backgroundSeedDraft = String(backgroundSettings.seed)
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
        pixelFiring?.fire(NewTabPageCustomizationPixel.allSettingsOpened, frequency: .dailyAndCount)
        onAllSettingsSelected?()
    }
}
