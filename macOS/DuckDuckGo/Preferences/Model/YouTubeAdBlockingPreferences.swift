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
import WebExtensions

struct YouTubeAdBlockingSettings: StoringKeys {
    let youTubeAdBlockingEnabled = StorageKey<Bool>(.youTubeAdBlockingEnabled)
    let youTubeAnalyticsEnabled = StorageKey<Bool>(.youTubeAnalyticsEnabled)
    let shouldHideYouTubeAdBlockingDisclosure = StorageKey<Bool>(.shouldHideYouTubeAdBlockingDisclosure)
    let youTubeAdBlockUnavailableNoticeShown = StorageKey<Bool>(.youTubeAdBlockUnavailableNoticeShown)
}

final class YouTubeAdBlockingPreferences: ObservableObject {

    static let youTubeAdBlockingEnabledDidChangeNotification = Notification.Name("youTubeAdBlockingEnabledDidChange")

    private var settings: any KeyedStoring<YouTubeAdBlockingSettings>
    private let pixelFiring: PixelFiring?
    private let adBlockingAvailability: AdBlockingAvailabilityProviding?
    private var cancellables = Set<AnyCancellable>()

    /// Mirrors `adBlockingAvailability.isDisabledUntilRelaunch` (when injected), updated via the
    /// shared change notification. Exposed as `@Published` so SwiftUI views observing this model
    /// (e.g. the Preferences pane) re-render the "Disabled until relaunch" sub-line on changes.
    @Published private(set) var isDisabledUntilRelaunch: Bool = false

    private var isHandlingExternalChange = false

    @Published
    var youTubeAdBlockingEnabled: Bool {
        didSet {
            guard youTubeAdBlockingEnabled != oldValue else { return }
            settings.youTubeAdBlockingEnabled = youTubeAdBlockingEnabled
            if !youTubeAdBlockingEnabled {
                youTubeAnalyticsEnabled = false
            }
            guard !isHandlingExternalChange else { return }
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
         pixelFiring: PixelFiring? = nil,
         adBlockingAvailability: AdBlockingAvailabilityProviding? = nil) {
        let resolvedSettings: any KeyedStoring<YouTubeAdBlockingSettings> = if let settings { settings } else { UserDefaults.standard.keyedStoring() }
        self.settings = resolvedSettings
        self.duckPlayerPreferences = duckPlayerPreferences ?? DuckPlayerPreferences()
        self.pixelFiring = pixelFiring
        self.adBlockingAvailability = adBlockingAvailability
        youTubeAdBlockingEnabled = resolvedSettings.youTubeAdBlockingEnabled ?? false
        isDisclosureHidden = resolvedSettings.shouldHideYouTubeAdBlockingDisclosure == true
        isDisabledUntilRelaunch = adBlockingAvailability?.isDisabledUntilRelaunch ?? false

        self.duckPlayerPreferences.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: Self.youTubeAdBlockingEnabledDidChangeNotification)
            .sink { [weak self] _ in
                self?.syncFromStore()
                self?.syncDisableUntilRelaunchFromAvailability()
            }
            .store(in: &cancellables)
    }

    /// Forwards the user-initiated Settings/popover toggle clear to the shared availability
    /// instance. No-op when no availability was injected (e.g. test fixtures).
    func clearDisableUntilRelaunch() {
        adBlockingAvailability?.clearDisableUntilRelaunch()
    }

    private func syncDisableUntilRelaunchFromAvailability() {
        let current = adBlockingAvailability?.isDisabledUntilRelaunch ?? false
        guard current != isDisabledUntilRelaunch else { return }
        isDisabledUntilRelaunch = current
    }

    /// Re-reads the persisted value when another instance posts the change notification, so
    /// multiple `YouTubeAdBlockingPreferences` instances (e.g. Settings pane + address-bar
    /// popover) stay in sync. Gated by `isHandlingExternalChange` to keep the pixel + notification
    /// from firing on the sync path.
    private func syncFromStore() {
        let stored = settings.youTubeAdBlockingEnabled ?? false
        guard stored != youTubeAdBlockingEnabled else { return }
        isHandlingExternalChange = true
        youTubeAdBlockingEnabled = stored
        isHandlingExternalChange = false
    }
}
