//
//  YouTubeAdBlockingPreferences.swift
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

import AppKit
import Combine
import DuckPlayer
import Foundation
import Persistence
import PixelKit
import PrivacyConfig
import SwiftUI

struct YouTubeAdBlockingSettings: StoringKeys {
    let youTubeAdBlockingEnabled = StorageKey<Bool>(.youTubeAdBlockingEnabled)
    let youTubeAnalyticsEnabled = StorageKey<Bool>(.youTubeAnalyticsEnabled)
    let shouldHideYouTubeAdBlockingDisclosure = StorageKey<Bool>(.shouldHideYouTubeAdBlockingDisclosure)
}

final class YouTubeAdBlockingPreferences: ObservableObject {

    static let youTubeAdBlockingEnabledDidChangeNotification = Notification.Name("youTubeAdBlockingEnabledDidChange")

    private var settings: any KeyedStoring<YouTubeAdBlockingSettings>
    private let pixelFiring: PixelFiring?
    private var cancellables = Set<AnyCancellable>()

    @Published
    var youTubeAdBlockingEnabled: Bool {
        didSet {
            guard youTubeAdBlockingEnabled != oldValue else { return }
            settings.youTubeAdBlockingEnabled = youTubeAdBlockingEnabled
            if !youTubeAdBlockingEnabled {
                youTubeAnalyticsEnabled = false
            }
            pixelFiring?.fire(
                youTubeAdBlockingEnabled ? WebExtensionPixel.adBlockingExtensionEnabled : WebExtensionPixel.adBlockingExtensionDisabled,
                frequency: .dailyAndCount)
            NotificationCenter.default.post(name: Self.youTubeAdBlockingEnabledDidChangeNotification, object: nil)
        }
    }

    var youTubeAnalyticsEnabled: Bool {
        get { settings.youTubeAnalyticsEnabled ?? false }
        set { settings.youTubeAnalyticsEnabled = newValue }
    }

    /// `nil` = never set; `true` = disclosure should be hidden; `false` = explicitly shown.
    @Published private(set) var isDisclosureHidden: Bool

    /// Settings-pane open hook. If the disclosure preference has never been
    /// written, pin it to the current YouTube Ad Blocking state — existing
    /// users (toggle already on) get the disclosure hidden, new users (toggle
    /// off) keep the disclosure until they explicitly opt in. Always refreshes
    /// `isDisclosureHidden` so external writes (e.g. debug menu) are picked up.
    func markDisclosureHiddenIfExistingUser() {
        if settings.shouldHideYouTubeAdBlockingDisclosure == nil {
            settings.shouldHideYouTubeAdBlockingDisclosure = youTubeAdBlockingEnabled
        }
        isDisclosureHidden = settings.shouldHideYouTubeAdBlockingDisclosure == true
    }

    var duckPlayerPreferences: DuckPlayerPreferences

    var duckPlayerMode: DuckPlayerMode {
        get { duckPlayerPreferences.duckPlayerMode }
        set { duckPlayerPreferences.duckPlayerMode = newValue }
    }

    var duckPlayerAutoplay: Bool {
        get { duckPlayerPreferences.duckPlayerAutoplay }
        set { duckPlayerPreferences.duckPlayerAutoplay = newValue }
    }

    var duckPlayerOpenInNewTab: Bool {
        get { duckPlayerPreferences.duckPlayerOpenInNewTab }
        set { duckPlayerPreferences.duckPlayerOpenInNewTab = newValue }
    }

    var shouldDisplayAutoPlaySettings: Bool {
        duckPlayerPreferences.shouldDisplayAutoPlaySettings
    }

    var isOpenInNewTabSettingsAvailable: Bool {
        duckPlayerPreferences.isOpenInNewTabSettingsAvailable
    }

    var isNewTabSettingsAvailable: Bool {
        duckPlayerPreferences.isNewTabSettingsAvailable
    }

    var youtubeOverlayInteracted: Bool {
        get { duckPlayerPreferences.youtubeOverlayInteracted }
        set { duckPlayerPreferences.youtubeOverlayInteracted = newValue }
    }

    var youtubeOverlayAnyButtonPressed: Bool {
        get { duckPlayerPreferences.youtubeOverlayAnyButtonPressed }
        set { duckPlayerPreferences.youtubeOverlayAnyButtonPressed = newValue }
    }

    var shouldDisplayContingencyMessage: Bool {
        duckPlayerPreferences.shouldDisplayContingencyMessage
    }

    func reset() {
        duckPlayerPreferences.reset()
    }

    @MainActor
    func openLearnMoreContingencyURL() {
        duckPlayerPreferences.openLearnMoreContingencyURL()
    }

    @MainActor
    func openLearnMoreURL() {
        guard let url = URL(string: "https://duckduckgo.com/duckduckgo-help-pages/privacy/detecting-ad-blocking-interference-anonymously") else { return }
        Application.appDelegate.windowControllersManager.show(url: url, source: .ui, newTab: true, selected: true)
    }

    init(settings: (any KeyedStoring<YouTubeAdBlockingSettings>)? = nil,
         duckPlayerPreferences: DuckPlayerPreferences? = nil,
         pixelFiring: PixelFiring? = nil) {
        let resolvedSettings: any KeyedStoring<YouTubeAdBlockingSettings> = if let settings { settings } else { UserDefaults.standard.keyedStoring() }
        self.settings = resolvedSettings
        self.duckPlayerPreferences = duckPlayerPreferences ?? DuckPlayerPreferences()
        self.pixelFiring = pixelFiring
        youTubeAdBlockingEnabled = resolvedSettings.youTubeAdBlockingEnabled ?? false
        isDisclosureHidden = resolvedSettings.shouldHideYouTubeAdBlockingDisclosure == true

        self.duckPlayerPreferences.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
