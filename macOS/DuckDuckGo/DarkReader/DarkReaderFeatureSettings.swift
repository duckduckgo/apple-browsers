//
//  DarkReaderFeatureSettings.swift
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

import AppKit
import Combine
import FeatureFlags
import Foundation
import Persistence
import PixelKit
import PrivacyConfig
import WebExtensions

protocol DarkReaderCurrentThemeProviding: AnyObject {
    var isLightTheme: Bool { get }
}

protocol DarkReaderFeatureSettings: DarkReaderExcludedDomainsProviding {

    var isFeatureEnabled: Bool { get }
    var isForceDarkModeEnabled: Bool { get }
    var excludedDomains: [String] { get }
    var forceDarkModeChangedPublisher: AnyPublisher<Bool, Never> { get }
    var excludedDomainsChangedPublisher: AnyPublisher<Void, Never> { get }
    func setForceDarkModeEnabled(_ enabled: Bool)
    func themeDidChange()
}

struct DarkReaderSettings: StoringKeys {
    let forceDarkModeOnWebsitesEnabled = StorageKey<Bool>(.forceDarkModeOnWebsites)
}

final class AppDarkReaderFeatureSettings: DarkReaderFeatureSettings {

    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private var storage: any ThrowingKeyedStoring<DarkReaderSettings>
    private let pixelFiring: PixelFiring?
    private weak var currentThemeProvider: DarkReaderCurrentThemeProviding?
    private let forceDarkModeChangedSubject = PassthroughSubject<Bool, Never>()
    private let excludedDomainsChangedSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    var forceDarkModeChangedPublisher: AnyPublisher<Bool, Never> {
        forceDarkModeChangedSubject.eraseToAnyPublisher()
    }

    var excludedDomainsChangedPublisher: AnyPublisher<Void, Never> {
        excludedDomainsChangedSubject.eraseToAnyPublisher()
    }

    init(featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         storage: (any ThrowingKeyedStoring<DarkReaderSettings>),
         currentThemeProvider: DarkReaderCurrentThemeProviding? = nil,
         pixelFiring: PixelFiring? = nil) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.storage = storage
        self.currentThemeProvider = currentThemeProvider
        self.pixelFiring = pixelFiring

        privacyConfigurationManager.updatesPublisher
            .sink { [weak self] in
                self?.excludedDomainsChangedSubject.send()
            }
            .store(in: &cancellables)

        (featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag>)?
            .flagDidChangePublisher
            .filter { $0.0 == .forceDarkModeOnWebsites }
            .sink { [weak self] _ in
                guard let self else { return }
                self.forceDarkModeChangedSubject.send(self.isForceDarkModeEnabled)
            }
            .store(in: &cancellables)
    }

    var isFeatureEnabled: Bool {
        guard #available(macOS 15.4, *) else { return false }
        guard featureFlagger.isFeatureOn(.webExtensions), currentThemeProvider?.isLightTheme != true else { return false }

        return featureFlagger.isFeatureOn(.forceDarkModeOnWebsites)
    }

    var isForceDarkModeEnabled: Bool {
        isFeatureEnabled && ((try? storage.forceDarkModeOnWebsitesEnabled) ?? false)
    }

    var excludedDomains: [String] {
        privacyConfigurationManager.privacyConfig.exceptionsList(forFeature: .forceDarkModeOnWebsites)
    }

    func setForceDarkModeEnabled(_ enabled: Bool) {
        guard isFeatureEnabled else { return }
        let previousValue = (try? storage.forceDarkModeOnWebsitesEnabled) ?? false
        guard previousValue != enabled else { return }
        try? storage.set(enabled, for: \.forceDarkModeOnWebsitesEnabled)
        pixelFiring?.fire(enabled ? WebExtensionPixel.darkReaderEnabled : WebExtensionPixel.darkReaderDisabled, frequency: .dailyAndCount)
        forceDarkModeChangedSubject.send(enabled)
    }

    func themeDidChange() {
        forceDarkModeChangedSubject.send(isForceDarkModeEnabled)
    }
}

extension AppearancePreferences: DarkReaderCurrentThemeProviding {

    var isLightTheme: Bool {
        return themeAppearance == .light
    }
}
