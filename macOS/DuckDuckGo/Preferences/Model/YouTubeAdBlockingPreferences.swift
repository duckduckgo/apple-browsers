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
import FeatureFlags
import Foundation
import Persistence
import PixelKit
import PrivacyConfig
import SwiftUI

struct YouTubeAdBlockingSettings: StoringKeys {
    let youTubeAdBlockingEnabled = StorageKey<Bool>(.youTubeAdBlockingEnabled)
    let youTubeAnalyticsEnabled = StorageKey<Bool>(.youTubeAnalyticsEnabled)
}

final class YouTubeAdBlockingPreferences: ObservableObject {

    static let youTubeAdBlockingEnabledDidChangeNotification = Notification.Name("youTubeAdBlockingEnabledDidChange")

    private var settings: any KeyedStoring<YouTubeAdBlockingSettings>
    private let pixelFiring: PixelFiring?
    private let featureFlagger: FeatureFlagger
    private var cancellables = Set<AnyCancellable>()

    /// Failsafe: when the corresponding remote flag is disabled, the analytics
    /// opt-in alert is suppressed and toggling YouTube Ad Blocking on goes
    /// straight through.
    var isAnalyticsOptInPromptEnabled: Bool {
        featureFlagger.isFeatureOn(.adBlockingAnalyticsOptInPrompt)
    }

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

    init(settings: (any KeyedStoring<YouTubeAdBlockingSettings>)? = nil,
         duckPlayerPreferences: DuckPlayerPreferences? = nil,
         pixelFiring: PixelFiring? = nil,
         featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger) {
        self.settings = if let settings { settings } else { UserDefaults.standard.keyedStoring() }
        self.duckPlayerPreferences = duckPlayerPreferences ?? DuckPlayerPreferences()
        self.pixelFiring = pixelFiring
        self.featureFlagger = featureFlagger
        youTubeAdBlockingEnabled = self.settings.youTubeAdBlockingEnabled ?? false

        self.duckPlayerPreferences.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
