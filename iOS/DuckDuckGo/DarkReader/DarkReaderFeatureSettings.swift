//
//  DarkReaderFeatureSettings.swift
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
import Core
import Foundation
import Persistence
import PrivacyConfig
import WebExtensions

protocol DarkReaderFeatureSettings: DarkReaderExcludedDomainsProviding {

    var isFeatureEnabled: Bool { get }
    var isForceDarkModeEnabled: Bool { get }
    var excludedDomains: [String] { get }
    var forceDarkModeChangedPublisher: AnyPublisher<Bool, Never> { get }
    var excludedDomainsChangedPublisher: AnyPublisher<Void, Never> { get }
    func setForceDarkModeEnabled(_ enabled: Bool)
    func themeDidChange()
}

enum DarkReaderStorageKeys: String, StorageKeyDescribing {
    case forceDarkModeOnWebsitesEnabled = "com_duckduckgo_darkReader_forceDarkModeOnWebsitesEnabled"
}

struct DarkReaderKeys: StoringKeys {
    let forceDarkModeOnWebsitesEnabled = StorageKey<Bool>(DarkReaderStorageKeys.forceDarkModeOnWebsitesEnabled)
}

final class AppDarkReaderFeatureSettings: DarkReaderFeatureSettings {

    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let appSettings: AppSettings
    private let storage: any KeyedStoring<DarkReaderKeys>
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
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         storage: (any KeyedStoring<DarkReaderKeys>)? = nil) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.appSettings = appSettings
        self.storage = if let storage { storage } else { UserDefaults.app.keyedStoring() }

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

    private var isLightTheme: Bool {
        appSettings.currentThemeStyle == .light
    }

    var isFeatureEnabled: Bool {
        guard #available(iOS 18.4, *) else { return false }
        guard !isLightTheme, featureFlagger.isFeatureOn(.webExtensions) else { return false }

        return featureFlagger.isFeatureOn(.forceDarkModeOnWebsites)
    }

    var isForceDarkModeEnabled: Bool {
        isFeatureEnabled && (storage.forceDarkModeOnWebsitesEnabled ?? false)
    }

    var excludedDomains: [String] {
        privacyConfigurationManager.privacyConfig.exceptionsList(forFeature: .forceDarkModeOnWebsites)
    }

    func setForceDarkModeEnabled(_ enabled: Bool) {
        guard isFeatureEnabled else { return }
        let previousValue = storage.forceDarkModeOnWebsitesEnabled ?? false
        guard previousValue != enabled else { return }
        storage.forceDarkModeOnWebsitesEnabled = enabled
        forceDarkModeChangedSubject.send(enabled)
    }

    func themeDidChange() {
        forceDarkModeChangedSubject.send(isForceDarkModeEnabled)
    }
}
